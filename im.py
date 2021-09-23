import requests


def imshow(img, name=''):
    if type(img) is ndarray:
        img = cv2.imencode('.png', img)[1]
    requests.post('https://proxy.hwangsehyun.com/imshow/', files={"File": img})


import cv2
from PIL import Image
from io import BytesIO
from pathlib import Path
from urllib.request import urlopen


def imread(img):
    if type(img) is np.ndarray:
        return img
    if not img.startswith("http"):
        return cv2.imread(img, cv2.IMREAD_GRAYSCALE)

    def JPG_PNG(img):
        return cv2.imdecode(np.asarray(bytearray(img), dtype="uint8"),
                            cv2.IMREAD_COLOR)

    return {
        ".gif": (lambda img: np.array(Image.open(BytesIO(img)).convert('RGB'))
                 [:, :, ::-1].copy()),
        ".jpg":
        JPG_PNG,
        ".png":
        JPG_PNG
    }[Path(img).suffix](urlopen(img).read())
