VERSION = "0.0.2"

local micro = import("micro")
local command = import("micro/command")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local os = import("os")
local filepath = import("path/filepath")

local treeBuffer
local viewBuffer

local openKey = "o"
local newFileKey = "n"
local newFolderKey = "f"

local treeTable = {}
local outView = ""

-- 1. Initialize the plugin
function init()
	-- ========== WORKING ==================
	config.MakeCommand("filetree", openTree, config.NoComplete)
end

-- Function on command mytree or filetree
function openTree(bp)
	viewBuffer = bp
	treeTable = fetchFiles(".")
	outView = treeTableToString(treeTable, 0)

	rebuildView()

	micro.CurPane():VSplitIndex(treeBuffer, true)

	micro.CurPane():ResizePane(180)
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

-- ==============================
-- =========== FINDING ==========
-- ===============================

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
	local cursorY = bp.Cursor.Loc.Y

	-- +1  0 to 1 (tables in lua are from 1)
	local node, _ = findItemByLine(treeTable, cursorY + 1, 0)

	-- For safety:
	if node == nil then
		return
	end

	if node.isDir then
		node.expanded = not node.expanded
		rebuildView()
	else
		-- openFile(viewBuffer, node.path)
		openFileInTab(viewBuffer, node.path)
	end
	bp.Cursor.Loc.Y = cursorY
end

function createFolder(bp)
	enterName(bp, "Folder", "Enter folder name")
end

function createFile(bp)
	enterName(bp, "File", "Enter file name")
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
			local err = os.Mkdir(fullPath, 0755)
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
		treeTable = fetchFiles(".")
		rebuildView()
		bp.Cursor.Loc.Y = cursorY
	end)
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
