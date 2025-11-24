VERSION = "0.0.1"

local micro = import("micro")
local command = import("micro/command")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local os = import("os")
local filepath = import("path/filepath")


local treeBuffer

local openKey = 'o'




-- 1. Initialize the plugin
function init()
    -- Create a command ':mytree'
    -- ========== WORKING ==================
    config.MakeCommand("mytree", openTree, config.NoComplete)

end

-- 2. The function that runs when you type :mytree
function openTree(bp)
    -- Run the 'ls' command to get file list, -a for getting also hidden files
    treeOutput = loadContentOfFolder(".")

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
    local treeTable = {}

    local out = loadContentOfFolder(homeFolder)

    for line in out:gmatch("[^\r\n]+") do
        table.insert(treeTable, fileNode(line, homeFolder))
    end

    return treeTable
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
    local treeTable = fetchFiles(".")
    local output = treeTableToString(treeTable,"")


    treeBuffer = buffer.NewBuffer(output, "fileTree")
    treeBuffer.Type.Scratch = true
    treeBuffer.Type.Readonly = true
    treeBuffer:SetOption("filetype", "mytree")
end



-- Possible TODOs:
-- maybe change to inserting instead of
