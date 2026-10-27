#!/bin/bash
# Только преобразование уже подготовленного master в стандартные размеры Xcode.
# Отделение фона не выполняется здесь: оно принадлежит подготовке утверждённого изображения.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT_DIR/Design/AppIcon-master.png"
CATALOG="$ROOT_DIR/Resources/Assets.xcassets"
[[ -f "$MASTER" ]] || { echo "Нет подготовленного master: $MASTER" >&2; exit 1; }
while read -r size scale pixels; do
    filename="icon_${size}x${size}"
    [[ "$scale" == "1" ]] || filename="$filename@${scale}x"
    if [[ "$pixels" == "1024" ]]; then
        # Master уже 1024px: один источник истины вместо побайтной копии в Git.
        ln -sfn ../../../Design/AppIcon-master.png "$CATALOG/AppIcon.appiconset/$filename.png"
    else
        /usr/bin/sips -z "$pixels" "$pixels" "$MASTER" --out "$CATALOG/AppIcon.appiconset/$filename.png" >/dev/null
    fi
done <<'SIZES'
16 1 16
16 2 32
32 1 32
32 2 64
128 1 128
128 2 256
256 1 256
256 2 512
512 1 512
512 2 1024
SIZES
/usr/bin/sips -z 512 512 "$MASTER" --out "$CATALOG/BrandMark.imageset/BrandMark.png" >/dev/null
echo "Размеры AppIcon и BrandMark подготовлены."
