#!/bin/sh
# Run a command against the patched GNUstep in the ois-dev container, on a
# fresh copy of this checkout.
#
#   .tools/gnustep.sh make test
#   .tools/gnustep.sh make examples
#
# ois-dev is the machine's GNUstep box (see ../gnustep-patches/CLAUDE.md):
# the whole stack is installed under /w/build. The checkout is copied in
# rather than mounted, with COPYFILE_DISABLE so macOS tar does not add an
# AppleDouble ._twin beside every file.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
container=${GNUSTEP_CONTAINER:-ois-dev}
dest=/w/udworkflow

if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
  echo "container $container is not running (docker ps -a | grep $container)" >&2
  exit 1
fi

(cd "$root" && COPYFILE_DISABLE=1 tar --no-mac-metadata -cf - --exclude .git --exclude obj \
    --exclude '*.bundle' .) \
  | docker exec -i "$container" sh -c "rm -rf $dest && mkdir -p $dest && tar xf - -C $dest"

exec docker exec -t "$container" bash -lc \
  "cd $dest && export LD_LIBRARY_PATH=/w/build/lib:\${LD_LIBRARY_PATH:-} \
   && set +u && . /w/build/System/Library/Makefiles/GNUstep.sh && $*"
