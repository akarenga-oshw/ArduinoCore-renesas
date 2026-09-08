#!/bin/bash

# Packages this core for the Arduino Boards Manager.
# Produces the core archive plus extras/package_akarenga_index.json (fixed name,
# so the URL published to users never changes).
#
# Unlike the upstream package.sh this script does not rewrite any tracked file:
# boards.txt and platform.txt are shipped exactly as they are committed.

set -e

if [ ! -f platform.txt ]; then
  echo Launch this script from the root core folder as ./extras/package_akarenga.sh
  exit 2
fi

if [ ! -d ../ArduinoCore-API ]; then
  git clone https://github.com/arduino/ArduinoCore-API.git ../ArduinoCore-API
fi

VERSION=`cat platform.txt | grep "version=" | cut -f2 -d"="`
FILENAME=ArduinoCore-renesas_uno-$VERSION.tar.bz2
INDEX=extras/package_akarenga_index.json
# git tag the release assets are attached to (see url in the template)
TAG=renesas-$VERSION
echo $VERSION

CORE_BASE=`basename $PWD`

# ship only the variants boards.txt actually refers to
KEEP_VARIANTS=`grep '^[a-z0-9_]*\.build\.variant=' boards.txt | cut -f2 -d'=' | sort -u`
EXCLUDE_VARIANTS=""
for DIR in variants/*/
do
    V=`basename $DIR`
    case " $KEEP_VARIANTS " in
        *" $V "*) ;;
        *) EXCLUDE_VARIANTS="$EXCLUDE_VARIANTS --exclude=$CORE_BASE/variants/$V" ;;
    esac
done

# bootloaders/ has no burn recipe in platform.txt, so nothing in the IDE can
# use it, and the UNO_R4 hex is still upstream's: it answers to 2341:0369,
# which boards.txt no longer looks for. Ours lives in its own repository.
#
# drivers/ and post_install.bat install a WinUSB .inf that only matches
# Arduino's VID/PID, so it never binds to this board. The bootloader and the
# core declare Microsoft OS 2.0 descriptors instead, which Windows acts on
# without any driver package at all.
EXCLUDE_UNUSED="--exclude=$CORE_BASE/bootloaders --exclude=$CORE_BASE/drivers --exclude=$CORE_BASE/post_install.bat"

cd ..
tar --exclude-tag-all=.portenta_only $EXCLUDE_VARIANTS $EXCLUDE_UNUSED --exclude='*.vscode*' --exclude='*.tar.*' --exclude='*.json*' --exclude='*.git*' --exclude='*e2studio*' --exclude='*extras*' -cjhf $FILENAME $CORE_BASE
cd -

mv ../$FILENAME .

CHKSUM=`sha256sum $FILENAME | awk '{ print $1 }'`
SIZE=`wc -c $FILENAME | awk '{ print $1 }'`

cat extras/package_akarenga_index.json.template |
sed "s/%%VERSION%%/${VERSION}/g" |
sed "s/%%TAG%%/${TAG}/g" |
sed "s/%%FILENAME_UNO%%/${FILENAME}/g" |
sed "s/%%CHECKSUM_UNO%%/${CHKSUM}/g" |
sed "s/%%SIZE_UNO%%/${SIZE}/g" > $INDEX

echo
echo "$FILENAME  ($SIZE bytes)"
echo "$INDEX"
echo
echo "publish with:"
echo "  gh release create $TAG $FILENAME -R akarenga-oshw/arduino-board-index -t $TAG"
