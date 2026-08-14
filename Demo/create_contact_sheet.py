from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


frames = sorted(Path("Demo/delivery-frames").glob("*.png"))
columns = 3
rows = 4
tile_width = 280
tile_height = 609
label_height = 32
gutter = 14

sheet = Image.new(
    "RGB",
    (
        columns * tile_width + (columns + 1) * gutter,
        rows * (tile_height + label_height) + (rows + 1) * gutter,
    ),
    "#e8e8e8",
)
draw = ImageDraw.Draw(sheet)
font = ImageFont.load_default(size=16)

for index, frame_path in enumerate(frames):
    row, column = divmod(index, columns)
    x = gutter + column * (tile_width + gutter)
    y = gutter + row * (tile_height + label_height + gutter)
    with Image.open(frame_path) as image:
        thumbnail = ImageOps.fit(image.convert("RGB"), (tile_width, tile_height))
        sheet.paste(thumbnail, (x, y))
    draw.text((x + 7, y + tile_height + 7), frame_path.stem, fill="#111111", font=font)

sheet.save("Demo/demo-contact-sheet.png", quality=95)
