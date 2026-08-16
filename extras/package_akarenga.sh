#!/bin/bash

# Packages the akarenga fork for the Arduino Boards Manager.
# Produces a core archive holding only the boards listed in KEEP_BOARDS, plus
# extras/package_akarenga_index.json (fixed name, so the URL never changes).

set -e

# boards to include in this package (boards.txt prefixes, space-separated)
KEEP_BOARDS="minima"

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

git checkout boards.txt
git checkout platform.txt

# comment out every board that is not in KEEP_BOARDS
ALL_BOARDS=`grep -o '^[a-z0-9_]*\.' boards.txt | sed 's/\.$//' | sort -u`
for BOARD in $ALL_BOARDS
do
    case " $KEEP_BOARDS " in
        *" $BOARD "*) ;;
        *) sed -i "s/^$BOARD\./#$BOARD./g" boards.txt ;;
    esac
done

sed -i 's/Arduino Renesas fsp Boards/Arduino Renesas UNO R4 Boards/g' platform.txt

CORE_BASE=`basename $PWD`

# exclude every variant that is not used by a kept board
KEEP_VARIANTS=""
for BOARD in $KEEP_BOARDS
do
    KEEP_VARIANTS="$KEEP_VARIANTS `grep "^$BOARD.build.variant=" boards.txt | cut -f2 -d'='`"
done

EXCLUDE_VARIANTS=""
for DIR in variants/*/
do
    V=`basename $DIR`
    case " $KEEP_VARIANTS " in
        *" $V "*) ;;
        *) EXCLUDE_VARIANTS="$EXCLUDE_VARIANTS --exclude=$CORE_BASE/variants/$V" ;;
    esac
done

cd ..
tar --exclude-tag-all=.portenta_only $EXCLUDE_VARIANTS --exclude='*.vscode*' --exclude='*.tar.*' --exclude='*.json*' --exclude='*.git*' --exclude='*e2studio*' --exclude='*extras*' -cjhf $FILENAME $CORE_BASE
cd -

mv ../$FILENAME .

git checkout boards.txt
git checkout platform.txt

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
