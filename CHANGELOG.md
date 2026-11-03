# Changelog

## 2.0.0

A rewrite of the whole package on luau-lsp's new type checker and Whiteoak's code style. It changes the API and the stored values, so a 1.5.0 key does not read correctly under 2.0.0: give every board a new key. The README's "Moving from 1.5.0" has the full table.

### Changed

- The methods are renamed: `:increment`, `:set`, `:save`, `:getAll`, `:delete` and `:destroy`, and the signals `.updated` and `.boardUpdated`.
- The automation table is `{ automation, interval, recordCount }`, and `recordCount` takes a table by board name as well as a number.
- A result is `{ board, rows }`, and a row is `{ rank, userId, value, username, displayName }`.
- A rolling board is `{ expirySeconds = n, key = "Key" }`.
- `:set` and `:destroy` return Promises, and `:destroy` returns its last save's.
- Every board reads highest first, and `:getAll` takes no sort direction.
- Promise and Signal are the Wally packages `evaera/promise@4.0.0` and `sleitnick/signal@^2`. A game that lists either itself adds a `[place]` block with `shared-packages`.
- The package is typed: a game requires it bare and keeps full types after `wally-package-types`.
- The realm is `server`, and the license is Apache 2.0, with Arxk's MIT notice in `NOTICE`.

### Added

- `:delete(boards, userId)` removes a player from each board and drops their queued amount.
- A `Weekly` board can reset on a weekday, hour and minute of its own, `{ key, weekday, hour?, minute? }`, and a `Daily` board at an hour and minute of its own, `{ key, hour, minute? }`, both in UTC. A key string keeps Sunday 00:00 and 00:00. A board whose reset time changes needs a new key, since its old key's totals count the old schedule's periods.
- `new` and every method check their arguments and throw on a bad one, before anything is queued or written.

### Removed

- `:SetValues`, since `:set` does a true set.
- The `debugMode` argument and its logger.
- `Yearly`, since a MemoryStore entry lives at most 45 days.

### Fixed

- Values are stored as the exact integers the game counted, where 1.5.0's encoding read every value at least one low and lost one more at every save.
- A failed read or save no longer stops the automation for good.
- A leaving player's queued amounts are saved, and the shutdown save finishes before the server closes.
- A failed write keeps its amount queued, and an amount queued while a save runs survives it.
- A list or a plain name of boards throws instead of doing nothing, and a name the object does not hold throws at the call instead of ending the automation.
- A rolling board's writes are atomic, and a failed read on one no longer wipes a player's value.
- A rolling board named like a period keeps its own expiry.
- Every row's `userId` is a number, and names are looked up in the background, nil until they arrive.
- An object that fails while being built holds no slot.
- `Automation` with no `interval` throws.

### Storage

- Each board but `AllTime` keeps only its top 100 rows, plus a slack of 20, in one MemoryStore sorted map, and each player's running total in a standard DataStore named by the board's key. MemoryStore memory no longer grows with the number of players who write in a window.
- Every object on a server shares one pool of at most 30 board writes in flight.
