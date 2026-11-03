--[[
    Loads a package's files fresh for each case under a fake game, script,
    require and task, over fake stores and a fake clock a second server can
    share, with Promise and Signal from the installed Packages/
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox")
local task = require("@lune/task")

local Clock = require("./Fakes/Clock")
local DataStoreService = require("./Fakes/DataStoreService")
local MemoryStoreService = require("./Fakes/MemoryStoreService")
local Players = require("./Fakes/Players")
local UserService = require("./Fakes/UserService")

local SOURCE: string = "src"
local PACKAGE: string = "Leaderboard"
local MODULE_FILE: string = "^(.+)%.luau$"
local LINK: string = `_Index%["([^"]+)"%]%["([^"]+)"%]` -- The folder a Wally link file points its alias at
local PENDING: string = "Started" -- Promise.Status.Started
local RESOLVED: string = "Resolved" -- Promise.Status.Resolved
local SETTLE_LIMIT: number = 600 -- Fake seconds settle advances before it fails the case
local CLOSE_LIMIT: number = 30 -- Fake seconds the engine gives the functions bound to close

-- Each dependency's module file inside the folder Wally installs it in
local DEPENDENCIES: { [string]: string } = {
	Promise = "lib/init.lua",
	Signal = "init.luau",
}

type Clock = Clock.Clock

type Backend = {
	clock: Clock,
	Signal: any, -- The harness's own Signal, running on Lune's task
	data: DataStoreService.Data,
	maps: MemoryStoreService.Maps,
	names: UserService.Names,
}

type Module = {
	path: string,
	source: string, -- Read when mounted, since a read yields and a require on a clocked thread must not
	loading: boolean,
	loaded: boolean,
	result: any,
}

export type Services = {
	DataStoreService: DataStoreService.DataStoreService,
	MemoryStoreService: MemoryStoreService.MemoryStoreService,
	Players: Players.Players,
	UserService: UserService.UserService,
}

export type Environment = {
	require: (path: string) -> any,
	clock: Clock,
	services: Services,
	close: () -> boolean,
	settle: (promise: any) -> (boolean, ...any),
}

export type Options = {
	server: Environment?, -- Another server's environment, whose stores and clock this one shares
	root: string?, -- The folder whose init.luau is the package, src by default
}

local Backends: { [any]: Backend } = setmetatable({} :: { [any]: Backend }, { __mode = "k" })

-- The status names a case compares a promise's getStatus with
local Environment = {
	PENDING = PENDING,
	RESOLVED = RESOLVED,
}

--[[
    Finds an installed dependency's module file through the link file
    Wally writes for its alias, so a new version needs no edit here
--]]

local function installed(alias: string): string
	local link: string = fs.readFile(`Packages/{alias}.lua`)
	local folder: string?, name: string? = link:match(LINK)
	assert(folder and name, `Packages/{alias}.lua names no installed folder; run wally install`)

	return `Packages/_Index/{folder}/{name}/{DEPENDENCIES[alias]}`
end

--[[
    The stores, names and clock one server or more run over. The clock's
    Signal runs on Lune's task, so it resumes a thread at once
--]]

local function backend(): Backend
	local path: string = installed("Signal")
	local Signal: any = luau.load(fs.readFile(path), { debugName = path, environment = { task = task } })()

	return {
		clock = Clock.new(Signal),
		Signal = Signal,
		data = { standard = {}, ordered = {} },
		maps = {},
		names = {},
	}
end

--[[
    Builds a server: the package's files under a ServerPackages folder
    beside Promise and Signal, loaded on first require, with fresh module
    state and fake services, over a new backend or another server's
--]]

function Environment.new(options: Options?): Environment
	local given: Options = options or {}
	local root: string = given.root or SOURCE

	local shared: Backend
	if given.server then
		shared = assert(Backends[given.server], "server takes an environment that Environment.new built")
	else
		shared = backend()
	end

	local clock: Clock = shared.clock
	local services: Services = {
		DataStoreService = DataStoreService.new(shared.data, clock.task.wait),
		MemoryStoreService = MemoryStoreService.new(shared.maps, clock),
		Players = Players.new(shared.Signal, clock.task.wait),
		UserService = UserService.new(shared.names, clock.task.wait),
	}

	local gameServices: { [string]: any } = table.clone(services :: { [string]: any })
	gameServices.RunService = { Heartbeat = clock.Heartbeat }

	local bound: { () -> () } = {}
	local modules: { [any]: Module } = {}
	local paths: { [string]: any } = {}
	local globals: { [string]: any } = {}

	--[[
	    The require the package's files see: runs a ModuleScript's file once,
	    with script set to it
	--]]

	local function load(module: any): any
		local record: Module? = modules[module]
		assert(record, `require was given {module}, which is no ModuleScript of this environment`)

		if record.loaded then
			return record.result
		end

		assert(not record.loading, `{module:GetFullName()} was required while it was still loading`)
		record.loading = true

		local scope: { [string]: any } = table.clone(globals)
		scope.script = module

		local chunk: (...any) -> ...any = luau.load(record.source, { debugName = record.path, environment = scope })
		local results: { n: number, [number]: any } = table.pack(chunk())
		assert(results.n == 1, `{record.path} returned {results.n} values, where a module returns exactly one`)

		record.loaded = true
		record.result = results[1]

		return results[1]
	end

	globals.require = load
	globals.task = clock.task
	globals.os = clock.os
	globals.DateTime = clock.DateTime
	globals.Enum = roblox.Enum
	globals.game = {
		GetService = function (_: any, name: string): any
			local service: any = gameServices[name]
			assert(service, `The fake game has no {name}`)

			return service
		end,

		BindToClose = function (_: any, callback: () -> ())
			table.insert(bound, callback)
		end,
	}

	--[[
	    A ModuleScript for one file, found again by its path below the root
	    without its extension
	--]]

	local function add(name: string, parent: any, path: string, relative: string?): any
		local module: any = roblox.Instance.new("ModuleScript")
		module.Name = name
		module.Parent = parent
		modules[module] = { path = path, source = fs.readFile(path), loading = false, loaded = false, result = nil }

		if relative then
			paths[relative] = module
		end

		return module
	end

	--[[
	    Maps a folder as Rojo does: a file is a ModuleScript, and a folder is
	    one too when it holds an init.luau
	--]]

	local function mount(parent: any, directory: string, prefix: string)
		for _, name: string in fs.readDir(directory) do
			local path: string = `{directory}/{name}`
			local stem: string? = name:match(MODULE_FILE)

			if fs.isDir(path) and fs.isFile(`{path}/init.luau`) then
				mount(add(name, parent, `{path}/init.luau`, `{prefix}{name}/init`), path, `{prefix}{name}/`)
			elseif fs.isDir(path) then
				local folder: any = roblox.Instance.new("Folder")
				folder.Name = name
				folder.Parent = parent
				mount(folder, path, `{prefix}{name}/`)
			elseif stem and stem ~= "init" then
				add(stem, parent, path, `{prefix}{stem}`)
			end
		end
	end

	local serverPackages: any = roblox.Instance.new("Folder")
	serverPackages.Name = "ServerPackages"

	mount(add(PACKAGE, serverPackages, `{root}/init.luau`, "init"), root, "")
	for alias: string in DEPENDENCIES do
		add(alias, serverPackages, installed(alias), nil)
	end

	local environment: Environment = {
		clock = clock,
		services = services,

		require = function (path: string): any
			local module: any = paths[path]
			assert(module, `{root} has no file {path}.luau`)

			return load(module)
		end,

		close = function (): boolean
			local returned: number = 0
			for _, callback: () -> () in bound do
				task.spawn(function ()
					callback()
					returned += 1
				end)
			end

			return clock.advanceUntil(function (): boolean
				return returned == #bound
			end, CLOSE_LIMIT)
		end,

		settle = function (promise: any): (boolean, ...any)
			local settled: boolean = clock.advanceUntil(function (): boolean
				return promise:getStatus() ~= PENDING
			end, SETTLE_LIMIT)
			assert(settled, `settle: the promise was still pending after {SETTLE_LIMIT} s of fake time`)

			return promise:await()
		end,
	}

	Backends[environment] = shared

	return environment
end

return Environment
