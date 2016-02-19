#!/bin/sh

#
#  build.sh
#
#  Copyright 2016 Avérous Julien-Pierre
#
#  This file is part of TorProxifier.
#
#  TorProxifier is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  TorProxifier is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with TorProxifier.  If not, see <http://www.gnu.org/licenses/>.
#
#

# Get base directory
base=$( dirname "$0" )
base=$( cd "${base}/../" ; pwd -P )

# Remove previous DMG.
if [ -f '/tmp/torproxifier_source.sparseimage' ]; then
	echo '[+] Remove previous temporary DMG.'
	
	rm '/tmp/torproxifier_source.sparseimage'
	
	if [ $? -ne 0 ]; then
		echo "[-] Error: Can't remove previous temporary DMG."
		exit 1	
	fi
fi

# Create temporary DMG
echo '[+] Create temporary DMG.'

/usr/bin/hdiutil create -size 100m -type SPARSE -fs 'HFS+' -volname 'SourceCache' -plist /tmp/torproxifier_source > /tmp/torproxifier_output.plist

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't create temporary DMG."
	exit 1	
fi

dmg_path=$(/usr/libexec/PlistBuddy -c 'Print :0' /tmp/torproxifier_output.plist)

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't obtain path of temporary DMG."
	exit 1	
fi

# Mount temporary DMG
echo '[+] Attach temporary DMG.'

/usr/bin/hdiutil attach "${dmg_path}" -nobrowse -plist > /tmp/torproxifier_output.plist

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't attach temporary DMG."
	exit 1	
fi

volume_path=$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:mount-point' /tmp/torproxifier_output.plist)

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't obtain path of attached DMG."
	exit 1	
fi

# Copy sources.
echo '[+] Copy sources to temporary DMG.'

/bin/cp -R "${base}/Externals" "${volume_path}/Externals"
/bin/cp -R "${base}/TorProxifier" "${volume_path}/TorProxifier"
/bin/cp -R "${base}/Workspace.xcworkspace" "${volume_path}/Workspace.xcworkspace"

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't copy sources."
	/usr/bin/hdiutil detach "${volume_path}" 1>/dev/null 2>/dev/null
	exit 1	
fi


# Get git hash.
echo '[+] Get source git hash.'

cd "${base}"
git rev-parse --short HEAD >  "${volume_path}/TorProxifier/git_hash.txt" 2>/Dev/null

if [ $? -ne 0 ]; then
	echo "[#] Warning: Can't get git hash."
	rm "${volume_path}/TorProxifier/git_hash.txt"
fi


# Compile.
echo '[+] Compile sources.'

cd "${volume_path}"

xcodebuild archive -workspace 'Workspace.xcworkspace' -scheme 'TorProxifier' -archivePath "${volume_path}/torproxifier.xcarchive" 1> "${volume_path}/build.txt" 2> "${volume_path}/build_err.txt"

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't build sources."
	cat "${volume_path}/build.txt"
	cat "${volume_path}/build_err.txt"
	/usr/bin/hdiutil detach "${volume_path}" 2>/dev/null 1>/dev/null
	exit 1
fi


# Export archive.
echo '[+] Export archive.'

cat > "${volume_path}/archive.plist" <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>4656ESDGU8</string>
</dict>
</plist>
EOL

xcodebuild -exportArchive -archivePath "${volume_path}/torproxifier.xcarchive" -exportPath "${volume_path}/output/" -exportOptionsPlist "${volume_path}/archive.plist" 1> "${volume_path}/build.txt" 2> "${volume_path}/build_err.txt"

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't export archive."
	cat "${volume_path}/build.txt"
	cat "${volume_path}/build_err.txt"
	/usr/bin/hdiutil detach "${volume_path}" 2>/dev/null 1>/dev/null
	exit 1
fi


# Create TorProxifier tarball.
echo '[+] Create TorProxifier tarball.'

cd "${volume_path}/output/"
/usr/bin/tar czf "TorProxifier.tgz" "TorProxifier.app"

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't create TorProxifier tarball."
	/usr/bin/hdiutil detach "${volume_path}" 2>/dev/null 1>/dev/null
	exit 1
fi

# Create TorProxifier Symbols tarball.
echo '[+] Create TorProxifier symbols tarball.'

cd "${volume_path}/torproxifier.xcarchive/dSYMs/"
/usr/bin/tar czf "TorProxifier-Symbols.tgz" "TorProxifier.app.dSYM"

if [ $? -ne 0 ]; then
	echo "[-] Error: Can't create TorProxifier symbols tarball."
	/usr/bin/hdiutil detach "${volume_path}" 2>/dev/null 1>/dev/null
	exit 1
fi

# Copy result.
echo '[+] Copy result.'

rm -rf "/Users/${USER}/Desktop/torproxifier-result/"
mkdir "/Users/${USER}/Desktop/torproxifier-result/"

cd "/Users/${USER}/Desktop/torproxifier-result/"

cp "${volume_path}/output/TorProxifier.tgz" "/Users/${USER}/Desktop/torproxifier-result/"
cp "${volume_path}/torproxifier.xcarchive/dSYMs/TorProxifier-Symbols.tgz" "/Users/${USER}/Desktop/torproxifier-result/"

open "/Users/${USER}/Desktop/torproxifier-result/"

# Clean.
echo '[+] Clean.'

/usr/bin/hdiutil detach "${volume_path}" 2>/dev/null 1>/dev/null

rm -f "${dmg_path}"
rm -f "/tmp/torproxifier_output.plist"
