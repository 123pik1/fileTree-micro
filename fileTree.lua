VERSION = "0.0.1"

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

local treeTable = {}
local outView = ""

-- 1. Initialize the plugin
function init()
    -- Create a command ':mytree'
    -- ========== WORKING ==================
    config.MakeCommand("mytree", openTree, config.NoComplete)
    config.MakeCommand("filetree", openTree, config.NoComplete)
end

-- 2. functions that catches eventes
-- catches special keys
function preAction(bp, action)

    return true
end

-- catches standard keys
function preRune(bp, action)
    if bp.Buf.Settings["filetype"] ~= "filetree" then return true end

    if action == openKey then
        -- micro.InfoBar("Opening")
        selectItem(bp)
        return false -- this blocks natural reaction
    end

    return true
end
-- 3.
-- Function on command mytree or filetree
function openTree(bp)
    viewBuffer = bp
    treeTable = fetchFiles(".")
    outView = treeTableToString(treeTable,"")


    -- treeOutput = loadContentOfFolder(".")

    rebuildView()

    -- Open a Vertical Split with this buffer
    micro.CurPane():VSplitIndex(treeBuffer, true)

    -- Resize it (make it small, like a sidebar)
    micro.CurPane():ResizePane(180)

    -- =========== TESTING ===============
    -- bp.HandleCommand("open ".."file")
end

function loadFolder(bp, folderName)
    shell.RunCommand("cd " .. folderName)
end

-- Loading content of specific directory
function loadContentOfFolder(folderName)
    -- shell.RunCommand("cd " .. folderName)
    local output, err = shell.RunCommand("ls -a -F '"..folderName.."'/")
    return output
end

-- Wrapper for opening file:
function openFile(bp, fileName)
    local newBuf, err = buffer.NewBufferFromFile(fileName)

    if err == nil then
        bp:OpenBuffer(newBuf)
    else
        micro.InfoBar():Error(err)
    end
end

function processKey(bp,key)

end

function fileNode(name, parentPath)
    local isDir = false
    local cleanName = name
    if string.sub(name, -1) == "/" then
        isDir = true
        cleanName = string.sub(name, 1, -2)
    end
    return {
     name = cleanName,
     path = filepath.Join(parentPath, name),
     isDir = isDir,
     expanded = false,
     children = {}
    }
end

function fetchFiles(homeFolder)
    local tabTree = {}

    local out = loadContentOfFolder(homeFolder)

    for line in out:gmatch("[^\r\n]+") do
        table.insert(tabTree, fileNode(line, homeFolder))
    end

    return tabTree
end

function treeTableToString(treeTable, stringToEveryLine)
    local tmp = ""

    for k,file in pairs(treeTable) do
        -- tmp = tmp..stringToEveryLine
        if file.name ~= "." and file.name ~=".." then
        if file.isDir then
            if file.expanded then
                tmp = tmp.."-"..file.name.."\n"
                file.children = fetchFiles(file.path)
                tmp = tmp..treeTableToString(file.children,stringToEveryLine.."  ")
            else
                tmp = tmp.."+"..file.name
            end
        else
            tmp = tmp.." "..file.name
        end
        tmp = tmp.."\n"
        end
    end
    return tmp
end

function rebuildView()
    outView = treeTableToString(treeTable, 0)
    if (treeBuffer~=nil) then
        treeBuffer.Type.Readonly = false
        treeBuffer:Replace(treeBuffer:Start(), treeBuffer:End(), outView)

        treeBuffer.Type.Readonly = true
        return
    end

    treeBuffer = buffer.NewBuffer(outView, "fileTree")
    treeBuffer.Type.Scratch = true
    treeBuffer.Type.Readonly = true
    treeBuffer:SetOption("filetype", "filetree")
end



function findItemByLine(nodes, lineId, currentLine)
    for _, file in pairs(nodes) do
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


function selectItem(bp)
    local cursorY = bp.Cursor.Loc.Y

    -- +3 to move from 0 to 1 (tables in lua are from 1) and skip . and ..
    local node, nodeId = findItemByLine(treeTable, cursorY+3, 0)

    -- For safety:
    if node == nil then
        return
    end

    if node.isDir then
        if node.expanded then
            node.expanded = false
        else
            node.expanded = true
        end
        rebuildView()
    else
        openFile(viewBuffer, node.path)
    end


end



-- Possible TODOs:
-- maybe change to inserting instead of
