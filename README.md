# Anixart Desktop

Unofficial desktop client (vibecoded) for Anixart, an anime library popular in the CIS. Written in C++ with Qt.

## Support

- Windows 10 x64 build 17763 (1809) or later
- Linux x86_64 (Debian 13 or later, Fedora 44 or later, and Arch Linux)

## Installation

Download the file for your system from the [Releases page](https://github.com/MikuImpulse/anixart_desktop/releases). Look in **Assets** for the files below.

### Windows

- **Installer** — If the release includes a setup file, download and run `Anixart-Setup-x64.exe`, then follow the setup steps. Open **Anixart** from the Start menu after installation. You can remove it from **Settings → Apps**.
- **Portable ZIP** — Download `Anixart-Windows-x64.zip`, extract the whole archive, and run `Anixart.exe` from the extracted `Anixart` folder. Keep the other files in the same folder.

### Linux

Use the package for your distro, or use the AppImage if the release includes one. The distro packages add **Anixart** to the app menu and let you start it from a terminal with `anixart-desktop`.

#### AppImage

Download the `.AppImage` file if one is listed under **Assets**. In a terminal, go to your download folder, replace `Anixart.AppImage` with the actual filename, and run these commands.

```bash
chmod +x ./Anixart.AppImage
./Anixart.AppImage
```

#### Debian (.deb)

```bash
sudo apt install ./anixart-desktop_VERSION_amd64.deb
```

#### Fedora (.rpm)

```bash
sudo dnf install ./anixart-desktop-VERSION.x86_64.rpm
```

#### Arch Linux (.pkg.tar.zst)

```bash
sudo pacman -U ./anixart-desktop-VERSION-x86_64.pkg.tar.zst
```

Run the command from your download folder and replace the example filename with the name of the file you downloaded.

## Known bugs

- Posting any comments is not working
- Changing the rating of a comment or post is not working
- There may be artifacts in the video player
- VKontakte (may be Yandex, Telegram too) authorization is not working

## P.S. for Anixart devs

i reversed your API from apk file to build this client. if you intended those details to stay private im sorry for publishing it in source code.

my username is **ishakbek**. if you’d like me to take the API source code down please send me an in-app notification, then i will remove the project or keep only the release packages available depending on what you are comfortable with
