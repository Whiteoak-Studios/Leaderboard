# Leaderboard

Leaderboard keeps time-windowed global leaderboards for a Roblox experience, on the server. One object holds up to seven boards, each a window over one stat: an hourly, daily, weekly or monthly board that empties at the end of each UTC period, with daily and weekly boards free to choose their own reset time, an all-time board, and rolling boards whose entries expire a fixed time after a player's first write. A game queues amounts in memory as play happens, and the object's automation saves them and reads every board's top rows on an interval.

Each board keeps only its top rows in a MemoryStore sorted map, with every player's running total in a standard DataStore, so its MemoryStore memory stays the same however many players write to it. Values are the exact whole numbers the game counted, every write is atomic across servers, and a failed write keeps its amount queued for the next save.

The package is `fadeluc-123/leaderboard` on Wally, realm `server`, under the Apache 2.0 license. It derives from Arxk's [Leaderboard](https://github.com/arxk/Leaderboard), and `NOTICE` carries that notice.

## Install

Add it to the game's `wally.toml` under `[server-dependencies]`:

```toml
[server-dependencies]
Leaderboard = "fadeluc-123/leaderboard@2.0.0"
```

Leaderboard depends on `evaera/promise@4.0.0` and `sleitnick/signal@^2`. A game that lists Promise or Signal itself under `[dependencies]` also needs a `[place]` block, or `wally install` stops with "A server or dev dependency is depending on a shared dependency" and leaves a half-written tree:

```toml
[place]
shared-packages = "game.ReplicatedStorage.Packages"
```

A game that lists neither needs no block, since Wally then installs both inside `ServerPackages/`.

### Typed install

Wally's link files carry no types, so after every `wally install` run these three steps, in this order, once each:

```sh
wally install
rojo sourcemap sourcemap.project.json --output sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages/
wally-package-types --sourcemap sourcemap.json ServerPackages/
```

`wally-package-types` 1.6.2 fails on a second pass over links it has already typed, so run the whole sequence again from `wally install` rather than repeating the last step. The project file is whichever one maps your place, such as `sourcemap.project.json` or `default.project.json`.

The package is written for luau-lsp's new type checker. Pass `--flag:LuauSolverV2=true` to every `luau-lsp analyze`, and give the editor the same checker in `.vscode/settings.json`:

```json
{
	"luau-lsp.fflags.enableNewSolver": true,
	"luau-lsp.fflags.enableByDefault": true,
	"luau-lsp.fflags.sync": false
}
```

The package then requires bare, with full types: a misspelled method or a handler of the wrong type is a type error in the game's own code. The new checker does not check each value of a plain boards table against `BoardConfig`, so annotate the local to have it checked, `local boards: { [string]: Leaderboard.BoardConfig } = { ... }`; `new` refuses a bad value at run time either way.

MemoryStoreService and DataStoreService answer in Studio only in a published place with Studio API access turned on in Game Settings.

## A short example

```lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerPackages = ServerScriptService.ServerPackages

local Leaderboard = require(ServerPackages.Leaderboard)

local kills = Leaderboard.new({
	AllTime = "Kills-AllTime-1",
	Daily = "Kills-Daily-1",
	KillsWipe = { expirySeconds = 604800, key = "Kills-Wipe-1" },
}, { automation = true, interval = 90, recordCount = 100 })

kills.boardUpdated:Connect(function (result: Leaderboard.BoardResult)
	print(`{result.board} has {#result.rows} rows`)
end)

local function onKill(killer: Player)
	kills:increment({ Daily = true, KillsWipe = true }, killer.UserId, 1)
end
```

`onKill` only adds to a queue in memory, so it is safe to call thousands of times a frame. Every 90 seconds the object reads each board's top 100 rows and fires its signals, and every 180 seconds it saves the queue.

## Boards and keys

`Leaderboard.new(boards, automation?)` takes a table mapping each board's name to its storage:

| Configuration | Board |
|---|---|
| `Hourly = "key"` | Empties at the end of each UTC hour. |
| `Daily = "key"` | Empties at the end of each UTC day, at 00:00 UTC. |
| `Daily = { key = "key", hour = h, minute = m? }` | Empties every day at h:m UTC. |
| `Weekly = "key"` | Empties at the end of each week, which starts on Sunday 00:00 UTC. |
| `Weekly = { key = "key", weekday = "Friday", hour = h?, minute = m? }` | Empties every week on that weekday at h:m UTC. |
| `Monthly = "key"` | Empties at the end of each UTC month. |
| `AllTime = "key"` | Never empties, and keeps each player's highest value. |
| `AnyName = { expirySeconds = n, key = "key" }` | Rolling: each player's entry lives `n` seconds from their first write. |

- A board's kind comes from its value, never from its name. A key string builds the window its name gives, so a key string is allowed only for those five names. A table with `expirySeconds` builds a rolling board under any name, `Daily` included, and a `Daily` or `Weekly` table with a reset time builds that window, turning at its own time.
- `Yearly` is refused, since a MemoryStore entry lives at most 45 days.
- A rolling expiry is a whole number of seconds from 60 to 3,888,000 (45 days).
- A key is 1 to 50 characters, the longest name a DataStore takes, and no two boards of one object share a key.
- One object holds 1 to 7 boards, and a server holds at most 3 live objects.
- A key names the board's stores, so a new key is a fresh, empty board. A key that carries a season or wipe number, such as `Kills-Wipe-{wipeNumber}`, starts a fresh board when the number changes, with no reset code.

`new` throws on any configuration it cannot build, and an object that fails partway holds no slot.

### Reset times

A `Daily` or `Weekly` board given as a table empties at a time of its own instead of at midnight or Sunday midnight:

```lua
local kills = Leaderboard.new({
	AllTime = "Kills-AllTime-1",
	Daily = { key = "Kills-Daily-1", hour = 14, minute = 30 },
	Weekly = { key = "Kills-Weekly-1", weekday = "Friday", hour = 14 },
}, { automation = true, interval = 90 })
```

Here `Daily` starts a new day every day at 14:30 UTC, and `Weekly` a new week every Friday at 14:00 UTC. A new period opens an empty board, and every player's total for it starts from zero, as at any period's end.

- `weekday` is one of `"Sunday"` to `"Saturday"`, `hour` a whole number from 0 to 23 and `minute` a whole number from 0 to 59. A `Weekly` table needs `weekday`, and its `hour` and `minute` default to 0. A `Daily` table needs `hour`, and its `minute` defaults to 0.
- Only `Weekly` takes `weekday`, and only `Weekly` and `Daily` take `hour` and `minute`. A table with `expirySeconds` is a rolling board and takes none of the three. `new` throws on anything else, naming the board.
- A key string keeps the default reset: 00:00 UTC for `Daily` and Sunday 00:00 UTC for `Weekly`. `Hourly` and `Monthly` always turn at the hour and the month.
- The time is UTC, which has no daylight saving, so a board resets at the same UTC time all year. Where the clocks change, its local reset time moves by an hour twice a year.
- To change a board's reset time, change its key as well. A board's stores are named by its key, so a new reset time on the old key leaves the current window mixing totals counted under the old schedule with the new one's. A new key starts the board empty on the new schedule.

`automation` is `{ automation = true, interval = seconds, recordCount = n? }`. `interval` is required whenever `automation` is true, and the `Automation` type always asks for it, so a missing interval is a type error before it is a run-time one. 90 to 120 seconds suits most games. `recordCount` is the number of rows each automated read takes, a number or a table by board name, and defaults to 100.

## Writing

Every method that names boards takes `"All"`, meaning every board the object holds, or a dictionary naming each board with `true`, such as `{ Daily = true, Weekly = true }`. A list, a plain name, an empty dictionary, or a name the object does not hold throws at the call, and nothing is queued or written.

Amounts and values are whole, non-negative, finite numbers. A fraction, a negative number, NaN or infinity throws, naming the value, so round what you pass. A user id is a whole number, and Studio's negative test ids are accepted.

- `:increment(boards, userId, amount)` adds to the queue in memory and never yields.
- `:set(boards, userId, value)` writes straight to the stores and returns a Promise. `value` is a number or a function `(old: number) -> number`. A bad number throws at the call. A function is held to the same rule when it returns, and a bad return rejects that board's write. It may run more than once, since `UpdateAsync` re-runs it when another server wrote the same player, so it computes only from `old`.
- `:save()` writes the queue and returns a Promise that settles once every write has. The saves of every object on the server share one pool of at most 30 writes in flight, the length of a server's DataStore request queue, so objects that save in the same tick never overflow it. A write that fails puts its amount back in the queue, added to anything queued since, and the Promise rejects once every write has settled.
- `:delete(boards, userId)` removes a player's entry from each board, drops their queued amount so the next save cannot bring it back, and returns a Promise. It first waits for every write the object has in flight, so an amount a failed write puts back is dropped too.

An `AllTime` board keeps each player's highest value, and a lower value is never written, so it suits a stat that only grows, such as total kills or the highest level reached. A stat that can go down belongs on a rolling or periodic board.

## Reading

`:getAll(boards, range?)` reads each board's highest rows and returns a Promise of a list of `BoardResult`:

```lua
type BoardResult = { board: string, rows: { Row } }
type Row = { rank: number, userId: number, value: number, username: string?, displayName: string? }
```

- Rows come highest first, at most 100 per board. `range` is a number from 1 to 100 or a table of such numbers by board name, and defaults to 100.
- Results come in the order of the boards' names, and the Promise rejects, naming each board, when any board's read fails.
- `username` and `displayName` are nil until a background lookup through `UserService` answers. A read never waits for a name: it takes what the cache holds and asks for the rest, so the next read has them. A name the lookup never returns stays nil, so show something of your own meanwhile.
- A player's row can trail their total by one save, since the row is written after the total lands.

## The automation and its signals

With `automation = true`, the object reads every board as soon as it is built, then every `interval` seconds, and saves the queue at every second read.

- `.updated` fires with the list of every board's `BoardResult` after each automated read, sorted by board name.
- `.boardUpdated` fires once per board with that board's `BoardResult`.

Both are `sleitnick/signal` signals, with `:Connect`, `:Once` and `:Wait`. A board that fails to read is left out of that read's signals, and a read where every board failed fires neither. A failed read or save warns and never stops the loop: the next interval tries again.

## Shutdown and destroy

- `:destroy()` ends the object's loop at once, disconnects every handler, frees its slot, makes a last save and returns that save's Promise. Any method called on a destroyed object throws.
- On server shutdown the package destroys every live object itself, and its `BindToClose` handler returns only once their last saves and any save, `:set` or `:delete` still in flight have settled, within Roblox's 30 seconds. A game needs no shutdown code of its own, and a player who leaves keeps their queued amounts until they are saved.

## How it stores a board

- `AllTime` is one OrderedDataStore named by its key, with each player's highest value under their user id.
- Every other board keeps its top 100 rows plus a slack of 20 in one MemoryStore sorted map, named `<key>:<period>` for a periodic board and `<key>` for a rolling one, and each player's running total in a standard DataStore named by its key, under their user id, beside the window it counts.
- Each save writes a player's total first. When the new total belongs on the board, because the board is not full, the total beats the lowest row, or the player is already on it, the save then writes their row, which expires when its window ends. Each read takes the map's top rows, keeps the lowest as the board's cutoff and removes the rows past the slack.
- A new period opens an empty map, and each player's total starts again from zero in it.

What this costs at scale is a paper estimate, made for 26 boards at 2,000 concurrent players: about 270 kB of MemoryStore memory, rising to about 750 kB at the Sunday rollover until the first reads trim it, and 8% to 21% of the MemoryStore request budget. It does not grow with the number of players who have ever written. The layout stops holding when servers average under about 8 players, since a server's reads cost the same at any size.

### Data the game owns

- A DataStore key never expires, so the totals of ended windows stay in their stores. A periodic board reuses one key per player, which each new window starts again. A rolling board whose key carries a wipe number gets a new totals store each wipe, and pruning the old ones is the game's.
- User ids are personal data under Roblox's right-to-be-forgotten rules. Every store keys its entries by user id, and a board's stores are named by keys the game chooses, so erasing a user from every board, past wipes included, is the game's. `:delete` removes a user from the current window of each board it names.

## Moving from 1.5.0

2.0.0 changes the API, and it stores exact integers where 1.5.0 stored a lossy encoding, so a board does not read a 1.5.0 key correctly. Give every board a new key.

| 1.5.0 | 2.0.0 |
|---|---|
| `:IncrementValues` | `:increment` |
| `:UpdateStoreValues` | `:set`, which returns a Promise |
| `:SetValues` | removed; `:set` does a true set |
| `:SaveValues` | `:save` |
| `:GetRecords(boards, range, sortDirection)` | `:getAll(boards, range)`, always highest first |
| `:Destroy` | `:destroy`, which returns its last save's Promise |
| `.Updated`, `.BoardUpdated` | `.updated`, `.boardUpdated` |
| `{ Automation, Interval, RecordCount }` | `{ automation, interval, recordCount }` |
| `{ Type, Data }` results | `{ board, rows }` |
| `{ Rank, UserId, Value, Username, DisplayName }` rows | `{ rank, userId, value, username, displayName }`, `userId` always a number |
| A rolling board's `{ 604800, "Key" }` | `{ expirySeconds = 604800, key = "Key" }` |
| `debugMode` | removed |
| A vendored Promise and Signal | `evaera/promise@4.0.0` and `sleitnick/signal@^2` |
| No way to remove an entry | `:delete(boards, userId)` |

## API

| Call | Returns | What it does |
|---|---|---|
| `Leaderboard.new(boards, automation?)` | `Leaderboard` | Builds an object of 1 to 7 boards, throwing on any configuration it cannot build. |
| `:increment(boards, userId, amount)` | nothing | Adds to the queue in memory. Never yields. |
| `:set(boards, userId, value)` | Promise | Writes a value, or a function of the old value, straight to the stores. |
| `:save()` | Promise | Writes the queue, at most 30 writes in flight across the server's saves, keeping failed amounts queued. |
| `:getAll(boards, range?)` | Promise of `{ BoardResult }` | Reads each board's highest rows, at most 100. |
| `:delete(boards, userId)` | Promise | Removes a player from each board and drops their queued amount. |
| `:destroy()` | Promise | Ends the loop, disconnects handlers, frees the slot and makes a last save. |
| `.updated` | Signal of `{ BoardResult }` | Fires after each automated read. |
| `.boardUpdated` | Signal of `BoardResult` | Fires once per board after each automated read. |

The exported types are `Leaderboard`, `BoardResult`, `Row`, `BoardConfig` and `Automation`, reached as `Leaderboard.BoardResult` and so on.

## Security

The package runs on the server only and exposes nothing to clients: it creates no remote and handles no client input. Take counts from the game's own server-side events, and send rows to clients through the game's own networking. Every public call checks its arguments and throws on a bad one before anything is queued or written.

## Developing the package

- `lune run tests` runs the Lune suite, which loads `src/` over fakes of MemoryStore, DataStore, Players and UserService that carry the real limits and errors, on a fake clock.
- `lune run format` formats the code in the house style.
- CI's `check` job runs the format check, `selene src`, `luau-lsp analyze` under the new checker and the suite on every pull request, and a `v*` tag publishes to Wally once `check` passes.
- `dev.project.json` builds the Studio dev place, with the package mounted at `ServerScriptService.ServerPackages.Leaderboard` beside its dependencies, as a game's install has it.
