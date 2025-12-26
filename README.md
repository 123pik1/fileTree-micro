# fileTree-micro

A lightweight file tree plugin for the [Micro](https://github.com/zyedidia/micro) text editor. This plugin adds a side view to browse and navigate your project's directory structure directly within the editor.

## Features

* **Project Navigation:** Easily browse folders and files in a tree structure.
* **Integration:** Opens files directly in the current Micro instance.
* **Customizable:** Configurable key bindings via `settings.json`.
* **Lightweight:** Written in Lua specifically for Micro.

## Installation

1.  Open your terminal.
2.  Navigate to your Micro plugins directory:
    * **Linux/macOS:** `~/.config/micro/plug`
    * **Windows:** `%userprofile%/.config/micro/plug`
3.  Clone this repository or download the ZIP and extract it:

    ```bash
    git clone [https://github.com/123pik1/fileTree-micro.git](https://github.com/123pik1/fileTree-micro.git)
    ```

    *Alternatively, download the ZIP from the releases page, unzip it, and place the folder into the `plug` directory.*

4.  Restart Micro.

## Usage

To use the file tree, follow these steps:

1.  **Open the Tree:**
    Press `Ctrl+E` to open the command bar, type `filetree`, and press `Enter`.
    *(Note: This command toggles the side pane).*

2.  **Navigate:**
    Use the **Arrow Keys** (Up/Down) to move through the directory list.

3.  **Open a File:**
    With a file selected in the tree pane, press **`o`** to open it in the editor.

## Configuration

You can customize the plugin's behavior, including key bindings, by modifying the `settings.json` file located in the plugin directory (`.../micro/plug/fileTree-micro/settings.json`).

## Known Issues & Limitations

* **Plugin Conflicts:** This plugin is currently known to conflict with the **bookmark plugin**.
* **Case Sensitivity:** Ensure commands are typed in lowercase, as capital letters may be interpreted differently by the plugin logic.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
