/**
 * Mock library data.
 *
 * Stands in for the file-manager backend (see Movieapp/backend `/list`) until
 * it's wired up. The Library screen browses this tree: the root holds movie
 * files and series folders; each series folder holds episode files. Selecting a
 * folder drills in, Back climbs out.
 */

export type LibraryFile = {
  id: string
  type: 'file'
  name: string
  /** Human-readable size, e.g. "2.1 GB". */
  size: string
  /** Resolution badge, e.g. "1080p". */
  resolution?: string
}

export type LibraryFolder = {
  id: string
  type: 'folder'
  name: string
  children: LibraryItem[]
}

export type LibraryItem = LibraryFile | LibraryFolder

/** Build the mock episode files for a series folder. */
function episodes(
  prefix: string,
  titles: string[],
  resolution: string,
  size: string,
): LibraryFile[] {
  return titles.map((title, i) => {
    const ep = String(i + 1).padStart(2, '0')
    return {
      id: `${prefix}-e${ep}`,
      type: 'file',
      name: `${prefix} - S01E${ep} - ${title}.mkv`,
      resolution,
      size,
    }
  })
}

export const LIBRARY_ROOT: LibraryItem[] = [
  // --- Movies (files, playable directly) ---
  {
    id: 'm-inception',
    type: 'file',
    name: 'Inception (2010) 1080p BluRay.mkv',
    resolution: '1080p',
    size: '2.4 GB',
  },
  {
    id: 'm-interstellar',
    type: 'file',
    name: 'Interstellar (2014) 2160p UHD.mkv',
    resolution: '4K',
    size: '8.1 GB',
  },
  {
    id: 'm-dark-knight',
    type: 'file',
    name: 'The Dark Knight (2008) 1080p.mp4',
    resolution: '1080p',
    size: '2.0 GB',
  },
  {
    id: 'm-dune-two',
    type: 'file',
    name: 'Dune Part Two (2024) 2160p.mkv',
    resolution: '4K',
    size: '9.3 GB',
  },
  {
    id: 'm-oppenheimer',
    type: 'file',
    name: 'Oppenheimer (2023) 1080p.mkv',
    resolution: '1080p',
    size: '3.2 GB',
  },

  // --- Series (folders of episodes) ---
  {
    id: 's-breaking-bad',
    type: 'folder',
    name: 'Breaking Bad',
    children: episodes(
      'Breaking Bad',
      ['Pilot', "Cat's in the Bag...", '...And the Bag\'s in the River', 'Cancer Man', 'Gray Matter'],
      '1080p',
      '1.6 GB',
    ),
  },
  {
    id: 's-stranger-things',
    type: 'folder',
    name: 'Stranger Things',
    children: episodes(
      'Stranger Things',
      ['The Vanishing of Will Byers', 'The Weirdo on Maple Street', 'Holly, Jolly', 'The Body', 'The Flea and the Acrobat'],
      '4K',
      '3.4 GB',
    ),
  },
  {
    id: 's-last-of-us',
    type: 'folder',
    name: 'The Last of Us',
    children: episodes(
      'The Last of Us',
      ['When You\'re Lost in the Darkness', 'Infected', 'Long, Long Time', 'Please Hold to My Hand', 'Endure and Survive'],
      '4K',
      '4.1 GB',
    ),
  },
  {
    id: 's-got',
    type: 'folder',
    name: 'Game of Thrones',
    children: episodes(
      'Game of Thrones',
      ['Winter Is Coming', 'The Kingsroad', 'Lord Snow', 'Cripples, Bastards, and Broken Things', 'The Wolf and the Lion'],
      '1080p',
      '2.2 GB',
    ),
  },
  {
    id: 's-the-bear',
    type: 'folder',
    name: 'The Bear',
    children: episodes(
      'The Bear',
      ['System', 'Hands', 'Brigade', 'Dogs', 'Sheridan'],
      '1080p',
      '1.4 GB',
    ),
  },
]

/**
 * Resolve a stack of folder ids to the items at that location. An empty stack
 * returns the root. An unknown id short-circuits to whatever was resolved so
 * far, so a stale path can't crash the browser.
 */
export function itemsAtPath(folderIds: string[]): LibraryItem[] {
  let level = LIBRARY_ROOT
  for (const id of folderIds) {
    const next = level.find((it) => it.id === id && it.type === 'folder') as
      | LibraryFolder
      | undefined
    if (!next) break
    level = next.children
  }
  return level
}
