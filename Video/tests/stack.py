"""Stack contact sheets vertically into one image: python3 stack.py out.png a.png b.png ..."""
import sys
from PIL import Image

ims = [Image.open(p).convert("RGB") for p in sys.argv[2:]]
W = max(i.width for i in ims)
out = Image.new("RGB", (W, sum(i.height for i in ims)), (40, 40, 40))
y = 0
for i in ims:
    out.paste(i, (0, y))
    y += i.height
out.save(sys.argv[1])
