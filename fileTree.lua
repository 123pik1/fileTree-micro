VERSION = "1.0.1"

local json = import("encoding/json")
local micro = import("micro")
local command = import("micro/command")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local os = import("os")
local filepath = import("path/filepath")

local treeBuffer
local viewBuffer

local settingsPath = "settings.json"
local workspacesPath = "workspaces.json"

local openKey = "o"
local newFileKey = "n"
local newFolderKey = "f"
local removeKey = "z"
local renameKey = "r"
local runKey = "e"
local alternativeOpenKey = "Enter"

local treeTable = {}
local outView = ""

local basePaneSize = 150

local baseDir

-- 1. Initialize the plugin
function init()
	if config.ConfigDir then
		settingsPath = filepath.Join(config.ConfigDir, "plug", "filetree", "settings.json")
		workspacesPath = filepath.Join(config.ConfigDir, "plug", "filetree", workspacesPath)
	else
		local home = os.Getenv("HOME") or os.Getenv("USERPROFILE")
		if home then
			settingsPath = filepath.Join(home, ".config/micro/plug/filetree/settings.json")
			workspacesPath = filepath.Join(home, ".config/micro/plug/filetree", workspacesPath)
		else
			settingsPath = "settings.json"
		end
	end

	loadVarsFromJson()
	-- ========== WORKING ==================
	config.MakeCommand("filetree", openTree, config.NoComplete)
	config.MakeCommand("ws-add", actualiseWorkspace, config.NoComplete)
	config.MakeCommand("ws-list", printWorkspaces, config.NoComplete)
	config.MakeCommand("ws-del", deleteWorkspace, config.NoComplete)
	-- config.MakeCommand("ws-open", openWorkspace, )

	baseDir, _ = os.Getwd()
end

function loadVarsFromJson()
	if not json then
		micro.InfoBar():Error("FileTree: JSON library not loaded")
		return
	end

	local file_handle, error_message = io.open(settingsPath, "r")

	if not file_handle then
		return
	end

	local json_string = file_handle:read("*a")

	file_handle:close()

	if json_string:sub(1, 1) ~= "{" then
		micro.InfoBar():Error("Settings corrupted: File does not start with '{'. Resetting.")
		return
	end

	if not json_string or json_string:match("^%s*$") then
		return
	end

	for key, val in json_string:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do
		if key == "open" then
			openKey = val
		end
		if key == "newFile" then
			newFileKey = val
		end
		if key == "newFolder" then
			newFolderKey = val
		end
		if key == "remove" then
			removeKey = val
		end
		if key == "rename" then
			renameKey = val
		end
		if key == "run" or key == "execute" then
			runKey = val
		end
	end
end

-- Function on command mytree or filetree
function openTree(bp)
	viewBuffer = bp
	treeTable = fetchFiles(baseDir)
	outView = treeTableToString(treeTable, 0)

	rebuildView()

	micro.CurPane():VSplitIndex(treeBuffer, true)

	micro.CurPane():ResizePane(basePaneSize)
end

-- =============================================
-- ================== REACTIONS =================
-- =============================================

function processAction(bp, action)
	if action == openKey then
		-- micro.InfoBar("Opening")
		selectItem(bp)
		return false -- this blocks natural reaction
	end
	if action == newFileKey then
		createFile(bp)
		return false
	end
	if action == newFolderKey then
		createFolder(bp)
		return false
	end
	if action == removeKey then
		remove(bp)
		return false
	end
	if action == renameKey then
		rename(bp)
		return false
	end
	if action == runKey then
		run(bp)
		return false
	end

	return true
end

-- catches special keys
function preAction(bp, action)
	if bp.Buf.Settings["filetype"] ~= "filetree" then
		return true
	end
	return processAction(bp, action)
end

-- catches standard keys
function preRune(bp, action)
	if bp.Buf.Settings["filetype"] ~= "filetree" then
		return true
	end
	return processAction(bp, action)
end

-- ========================================
-- ================= FETCHING =============
-- ========================================
function loadFolder(folderName)
	shell.RunCommand("cd " .. folderName)
end

-- Loading content of specific directory
function loadContentOfFolder(folderName)
	local output, err = shell.RunCommand("ls -a -F '" .. folderName .. "'/")
	return output
end

function fetchFiles(homeFolder)
	local tabTree = {}

	local out = loadContentOfFolder(homeFolder)

	for line in out:gmatch("[^\r\n]+") do
		if line ~= "./" and line ~= "../" then
			table.insert(tabTree, fileNode(line, homeFolder))
		end
	end

	return tabTree
end

function getWorkspaces()
	-- if there is no file - return empty table
	local _, err = os.Stat(workspacesPath)
	if err ~= nil then
		return {}
	end

	-- workspaces from file set
	local ws = nil

	local file_handle, error_message = io.open(workspacesPath, "r")

	if file_handle == nil then
		return
	end

	local json_string = file_handle:read("*a")

	file_handle:close()

	local workspaces = {}

	-- emergency function for decoding json
	for name, path in json_string:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do
		table.insert(workspaces, workspace(name, path))
	end

	return workspaces
end

-- =======================================
-- =============== FILE OPENING ==========
-- =======================================

-- Wrapper for opening file:
function openFile(bp, fileName)
	local newBuf, err = buffer.NewBufferFromFile(fileName)

	if err == nil then
		bp:OpenBuffer(newBuf)
	else
		micro.InfoBar():Error(err)
	end
end

function openFileInTab(bp, filePath)
	local cmd = string.format("tab %q", filePath)
	bp:HandleCommand(cmd)
end

-- =========================================
-- ============== PARSING DATA ==============
-- =========================================

function treeTableToString(treeTab, depth)
	local tmp = ""
	local indent = string.rep(" ", depth)
	for k, file in ipairs(treeTab) do
		tmp = tmp .. indent
		if file.name ~= "." and file.name ~= ".." then
			if file.isDir then
				if file.expanded then
					tmp = tmp .. "-" .. file.name .. "\n"
					if #file.children == 0 then
						file.children = fetchFiles(file.path)
					end
					tmp = tmp .. treeTableToString(file.children, depth + 1)
				else
					tmp = tmp .. "+" .. file.name .. "\n"
				end
			else
				tmp = tmp .. " " .. file.name .. "\n"
			end
		end
	end
	return tmp
end

function fileNode(name, parentPath)
	local isDir = false
	local cleanName = name
	if string.sub(name, -1) == "/" then
		isDir = true
		cleanName = string.sub(name, 1, -2)
	end
	local lastChar = string.sub(cleanName, -1)
	if lastChar == "*" or lastChar == "@" or lastChar == "|" or lastChar == "=" then
		cleanName = string.sub(cleanName, 1, -2)
	end

	return {
		name = cleanName,
		path = filepath.Join(parentPath, cleanName),
		isDir = isDir,
		expanded = false,
		children = {},
	}
end

function workspace(name, path)
	return {
		name = name,
		path = path,
	}
end

-- ==============================
-- =========== FINDING ==========
-- ==============================

function findItemByLine(nodes, lineId, currentLine)
	for _, file in ipairs(nodes) do
		currentLine = currentLine + 1

		if currentLine == lineId then
			return file, currentLine
		end

		if file.isDir and file.expanded then
			local foundNode, updatedLine = findItemByLine(file.children, lineId, currentLine)

			if foundNode then
				return foundNode, updatedLine
			end

			currentLine = updatedLine
		end
	end

	return nil, currentLine
end

-- ===============================
-- ============ ACTIONS ==========
-- ===============================

function selectItem(bp)
	if bp.Buf.Settings["filetype"] ~= "filetree" then
		return
	end

	local cursorY = bp.Cursor.Loc.Y

	-- +1  0 to 1 (tables in lua are from 1)
	local node, _ = findItemByLine(treeTable, cursorY + 1, 0)

	-- For safety:
	if node == nil then
		return
	end
	micro.InfoBar():Message(node.path)

	if node.isDir then
		node.expanded = not node.expanded
		rebuildView()
	else
		openFileInTab(viewBuffer, node.path)
	end
	bp.Cursor.Loc.Y = cursorY
end

function createFolder(bp)
	enterName(bp, "Folder", "Enter folder name ")
end

function createFile(bp)
	enterName(bp, "File", "Enter file name ")
end

function enterName(bp, option, promptMessage)
	-- option is to choose if file is created or folder
	local cursorY = bp.Cursor.Loc.Y

	local node, _ = findItemByLine(treeTable, cursorY + 1, 0)

	if node == nil then
		return
	end

	micro.InfoBar():Prompt(promptMessage, "", "file", nil, function(input)
		if input == "" then
			return
		end
		local path = node.path

		if node.isDir == false then
			path = filepath.Dir(path)
		end

		local fullPath = path .. "/" .. input

		if option == "Folder" then
			local err = os.Mkdir(fullPath, 777)
			if err ~= nil then
				micro.InfoBar():Error("Error creating folder: " .. tostring(err))
			else
				micro.InfoBar():Message("Folder created: " .. input)
			end
		elseif option == "File" then
			local file, err = io.open(fullPath, "w")
			if file then
				file:close()
				micro.InfoBar():Message("File created: " .. input)
			else
				micro.InfoBar():Error("Error creating file: " .. tostring(err))
			end
		end
		treeTable = fetchFiles(baseDir)
		rebuildView()
		bp.Cursor.Loc.Y = cursorY
	end)
end

-- removes file or folder
function remove(bp)
	local cursorY = bp.Cursor.Loc.Y
	local node, _ = findItemByLine(treeTable, cursorY + 1, 0)

	if node == nil then
		return
	end
	micro.InfoBar():Prompt("Are you sure you want to delete? [y/n] ", "", "file", nil, function(input)
		if input ~= "y" and input ~= "Y" then
			return
		end
		local err
		if node.isDir then
			-- local err = os.Rmdir
			err = shell.RunCommand('rm -r "' .. node.path .. '"')
		else
			err = shell.RunCommand('rm "' .. node.path .. '"')
		end
		treeTable = fetchFiles(baseDir)
		rebuildView()
	end)
end

function rename(bp)
	local cursorY = bp.Cursor.Loc.Y
	local node, _ = findItemByLine(treeTable, cursorY + 1, 0)

	if node == nil then
		return
	end

	micro.InfoBar():Prompt("How would you like to name this file? ", "", "file", nil, function(input)
		if input == "" then
			return
		end

		local newPath = filepath.Dir(node.path) .. "/" .. input

		local err = shell.RunCommand('mv "' .. node.path .. '" "' .. newPath .. '"')

		treeTable = fetchFiles(baseDir)
		rebuildView()
		bp.Cursor.Loc.Y = cursorY
	end)
end

function run(bp)
	local cursorY = bp.Cursor.Loc.Y
	local node, _ = findItemByLine(treeTable, cursorY + 1, 0)

	micro.InfoBar():Message(node.path)
	if node == nil then
		return
	end

	local cmd = string.format("%q", node.path)

	shell.RunCommand("chmod +x " .. cmd)
	shell.RunInteractiveShell(cmd, true, false)
end

function deleteWorkspace(bp, workspace)
	micro.InfoBar():Prompt("Enter workspace for delete ", "", "workspace", nil, function(input)
		if input == "" then
			return
		end

		local ws_s = getWorkspaces(bp)
		local new_ws_s = {}

		local deleted = false

		for _, element in ipairs(ws_s) do
			if element.name ~= input then
				table.insert(new_ws_s, element)
			else
				deleted = true
				micro.InfoBar():Message("Workspace being deleted")
			end
		end

		if not deleted then
			micro.InfoBar():Message("There is no workspace with this name")
		end

		saveWorkspaces(bp, new_ws_s)

		-- micro.InfoBar():Message("Workspace deleted")
		micro.InfoBar():Message(new_ws_s)
	end)
end

function saveWorkspaces(bp, workspaces)
	local data = "{\n"

	for index, element in ipairs(workspaces) do
		data = data .. '"' .. element.name .. '" : "' .. element.path .. '"\n'
	end

	data = data .. "\n}"

	local file_handle, err = io.open(workspacesPath, "w")

	if file_handle then
		file_handle:write(data)

		file_handle:close()
	else
		micro.InfoBar:Message("error opening file to save")
	end
end

-- modifies existing workspace or adds new
-- no input function returns - expected behaviour
function actualiseWorkspace(bp)
	micro.InfoBar():Prompt(
		"Enter name for workspace to which this directory should belong (if name alread exists it will be rewritten) ",
		"",
		"worskpace",
		nil,
		function(input)
			if input == "" then
				return
			end

			-- all workspaces
			local ws_s = getWorkspaces(bp)
			local found = false

			for _, ws in ipairs(ws_s) do
				if ws.name == input then
					ws.path = baseDir
					found = true
					break
				end
			end

			if not found then
				table.insert(ws_s, workspace(input, baseDir))
			end
			saveWorkspaces(bp, ws_s)
		end
	)
end

-- creates workspace
function createWorkspace(bp)
	actualiseWorkspace(bp)
end

-- ===========================
-- =========== VIEW ==========
-- ===========================

function rebuildView()
	outView = treeTableToString(treeTable, 0)
	if treeBuffer ~= nil then
		treeBuffer.Type.Readonly = false
		treeBuffer:Replace(treeBuffer:Start(), treeBuffer:End(), outView)

		treeBuffer.Type.Readonly = true
		return
	end

	treeBuffer = buffer.NewBuffer(outView, "fileTree")
	treeBuffer.Type.Scratch = true
	treeBuffer.Type.Readonly = true
	treeBuffer:SetOption("filetype", "filetree")
	treeBuffer:SetOption("softwrap", "false")
	treeBuffer:SetOption("ruler", "false")
	treeBuffer:SetOption("statusformatl", "File Tree")
	treeBuffer:SetOption("statusformatr", "")
end

function printWorkspaces(bp)
	workspaces = getWorkspaces()

	local output = ""

	local count = 0

	for key, workspaceElement in pairs(workspaces) do
		output = output .. string.format("%-20s %s", workspaceElement.name, workspaceElement.path) .. "\n"
		count = count + 1
	end

	if count == 0 then
		output = output .. "Currently there are no workspaces added"
	end

	local bufferForWs = buffer.NewBuffer(output, "Workspaces")

	bp:HSplitBuf(bufferForWs)
end
