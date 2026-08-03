const HttpService = game:GetService("HttpService")
const Data = require("./Data")

export type Snippet = {
	id: string,
	name: string,
	aliases: { string },
	source: string,
	favorite: boolean,
}

export type Scope = "global" | "workspace"

export type Store = {
	changed: RBXScriptSignal,
	get: (Scope?) -> { Snippet },
	add: (Scope, string, { string }, string) -> Snippet?,
	update: (Scope, string, string, { string }, string) -> boolean,
	remove: (Scope, string) -> (),
	duplicate: (Scope, string) -> (),
	toggleFavorite: (Scope, string) -> (),
	refreshWorkspace: () -> (),
	destroy: () -> (),
}

const GLOBAL_SETTING_KEY = "CodeKitSnippets"
const WORKSPACE_SNIPPETS_NAME = "_CODEKIT_SNIPPETS"
const MAX_SNIPPETS = 500
const MAX_SNIPPET_NAME_LENGTH = 128
const MAX_SNIPPET_ALIAS_LENGTH = 128
const MAX_SNIPPET_SOURCE_LENGTH = 100_000

const function cloneAliases(aliases: { string }): { string }
	const cloned = {}
	for _, alias in aliases do
		table.insert(cloned, alias)
	end
	return cloned
end

const function cloneSnippet(snippet: Snippet): Snippet
	return {
		id = snippet.id,
		name = snippet.name,
		aliases = cloneAliases(snippet.aliases),
		source = snippet.source,
		favorite = snippet.favorite == true,
	}
end

const function normalizeAliases(value: any): { string }
	if typeof(value) ~= "table" then
		return {}
	end

	const aliases = {}
	const seen = {}
	for _, rawAlias in value do
		if typeof(rawAlias) ~= "string" then
			continue
		end

		const alias = string.gsub(rawAlias, "^%s*(.-)%s*$", "%1")
		if alias == "" or #alias > MAX_SNIPPET_ALIAS_LENGTH or seen[alias] == true then
			continue
		end

		seen[alias] = true
		table.insert(aliases, alias)
	end
	return aliases
end

const function normalizeSnippets(value: any): { Snippet }
	if typeof(value) ~= "table" then
		return {}
	end

	const snippets = {}
	const seenIds = {}
	for _, item in value do
		if #snippets >= MAX_SNIPPETS then
			break
		end
		if typeof(item) ~= "table" or typeof(item.name) ~= "string" or item.name == "" then
			continue
		end
		if #item.name > MAX_SNIPPET_NAME_LENGTH then
			continue
		end

		local source = if typeof(item.source) == "string" then item.source else ""
		if #source > MAX_SNIPPET_SOURCE_LENGTH then
			continue
		end

		local id = if typeof(item.id) == "string" and item.id ~= "" then item.id else HttpService:GenerateGUID(false)
		if seenIds[id] == true then
			id = HttpService:GenerateGUID(false)
		end
		seenIds[id] = true

		table.insert(snippets, {
			id = id,
			name = item.name,
			aliases = normalizeAliases(item.aliases),
			source = source,
			favorite = item.favorite == true,
		})
	end

	table.sort(snippets, function(a, b)
		if a.favorite ~= b.favorite then
			return a.favorite
		end
		return string.lower(a.name) < string.lower(b.name)
	end)

	return snippets
end

const function cloneSnippets(snippets: { Snippet }): { Snippet }
	const cloned = {}
	for _, snippet in snippets do
		table.insert(cloned, cloneSnippet(snippet))
	end
	return cloned
end

const function loadWorkspaceSnippets(): { Snippet }
	return normalizeSnippets(Data.loadWorkspace(WORKSPACE_SNIPPETS_NAME, {}))
end

const function saveWorkspaceSnippets(snippets: { Snippet })
	Data.saveWorkspace(WORKSPACE_SNIPPETS_NAME, "edit snippets from the plugin snippets window", snippets)
end

const function create(plugin: Plugin): Store
	local globalSnippets = normalizeSnippets(Data.load(plugin, GLOBAL_SETTING_KEY, {}))
	local workspaceSnippets = loadWorkspaceSnippets()
	const changed = Instance.new("BindableEvent")

	const function save(scope: Scope)
		if scope == "global" then
			globalSnippets = normalizeSnippets(globalSnippets)
			Data.save(plugin, GLOBAL_SETTING_KEY, globalSnippets)
		else
			workspaceSnippets = normalizeSnippets(workspaceSnippets)
			saveWorkspaceSnippets(workspaceSnippets)
		end
		changed:Fire()
	end

	const function getScopeList(scope: Scope): { Snippet }
		return if scope == "global" then globalSnippets else workspaceSnippets
	end

	const function setScopeList(scope: Scope, snippets: { Snippet })
		if scope == "global" then
			globalSnippets = snippets
		else
			workspaceSnippets = snippets
		end
	end

	return {
		changed = changed.Event,
		get = function(scope: Scope?): { Snippet }
			if scope == nil then
				const all = cloneSnippets(globalSnippets)
				for _, snippet in workspaceSnippets do
					table.insert(all, cloneSnippet(snippet))
				end
				return normalizeSnippets(all)
			end
			return cloneSnippets(getScopeList(scope))
		end,
		add = function(scope: Scope, name: string, aliases: { string }, source: string): Snippet?
			const snippets = getScopeList(scope)
			if name == "" or #name > MAX_SNIPPET_NAME_LENGTH or #source > MAX_SNIPPET_SOURCE_LENGTH then
				return nil
			end
			if #snippets >= MAX_SNIPPETS then
				return nil
			end
			const snippet = {
				id = HttpService:GenerateGUID(false),
				name = name,
				aliases = normalizeAliases(aliases),
				source = source,
				favorite = false,
			}
			table.insert(snippets, snippet)
			setScopeList(scope, snippets)
			save(scope)
			return cloneSnippet(snippet)
		end,
		update = function(scope: Scope, id: string, name: string, aliases: { string }, source: string): boolean
			if name == "" or #name > MAX_SNIPPET_NAME_LENGTH or #source > MAX_SNIPPET_SOURCE_LENGTH then
				return false
			end
			const snippets = getScopeList(scope)
			for _, snippet in snippets do
				if snippet.id == id then
					snippet.name = name
					snippet.aliases = normalizeAliases(aliases)
					snippet.source = source
					save(scope)
					return true
				end
			end
			return false
		end,
		remove = function(scope: Scope, id: string)
			const snippets = getScopeList(scope)
			for index, snippet in snippets do
				if snippet.id == id then
					table.remove(snippets, index)
					save(scope)
					return
				end
			end
		end,
		duplicate = function(scope: Scope, id: string)
			const snippets = getScopeList(scope)
			if #snippets >= MAX_SNIPPETS then
				return
			end
			for _, snippet in snippets do
				if snippet.id == id then
					table.insert(snippets, {
						id = HttpService:GenerateGUID(false),
						name = `{snippet.name} Copy`,
						aliases = cloneAliases(snippet.aliases),
						source = snippet.source,
						favorite = false,
					})
					save(scope)
					return
				end
			end
		end,
		toggleFavorite = function(scope: Scope, id: string)
			const snippets = getScopeList(scope)
			for _, snippet in snippets do
				if snippet.id == id then
					snippet.favorite = not snippet.favorite
					save(scope)
					return
				end
			end
		end,
		refreshWorkspace = function()
			workspaceSnippets = loadWorkspaceSnippets()
			changed:Fire()
		end,
		destroy = function()
			changed:Destroy()
		end,
	}
end

return {
	create = create,
	WORKSPACE_SNIPPETS_NAME = WORKSPACE_SNIPPETS_NAME,
}
