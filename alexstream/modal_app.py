"""
Modal deployment for the AlexStream backend.

This runs the existing Node.js API server (backend/server.js) unchanged: the
image installs Node 20, copies the backend, runs `npm install`, and serves
`node server.js` behind a Modal web endpoint.

Deploy:
    pip install modal
    modal setup                 # one-time auth
    modal deploy modal_app.py

Modal prints a public URL like:
    https://<you>--alexstream-serve.modal.run
Put that URL in the Android app (BackendConfig.kt / window.__BACKEND_BASE).

Secrets: the values in backend/.env are read at deploy time via from_dotenv and
injected as environment variables in the container. No .env is shipped in the
image; never commit real secrets.
"""

from pathlib import Path

import modal

BACKEND_DIR = Path(__file__).parent / "backend"
PORT = 3000

image = (
    modal.Image.debian_slim()
    .apt_install("curl")
    .run_commands(
        "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -",
        "apt-get install -y nodejs",
    )
    # Copy the backend source (excluding local-only files) and install deps in
    # the image so cold starts don't re-run npm install.
    .add_local_dir(
        BACKEND_DIR,
        remote_path="/app",
        copy=True,
        ignore=["node_modules", ".env", "*.log"],
    )
    .run_commands("cd /app && npm install --omit=dev")
)

app = modal.App("alexstream")


@app.function(
    image=image,
    secrets=[modal.Secret.from_dotenv(BACKEND_DIR)],
    min_containers=1,  # keep one warm so the TV app isn't hit with cold starts
)
@modal.concurrent(max_inputs=100)
@modal.web_server(PORT, startup_timeout=60)
def serve():
    import subprocess

    subprocess.Popen(
        "node server.js",
        cwd="/app",
        shell=True,
    )
