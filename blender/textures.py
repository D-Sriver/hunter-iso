"""Textures procédurales du kit, générées avec numpy (aucune image externe).

Chaque fonction rend un tableau float32 de forme (taille, taille, 4) en RGBA linéaire,
origine en bas à gauche comme les pixels Blender.
"""

import numpy as np

SIZE = 512


def _rng(seed):
    return np.random.default_rng(seed)


def _value_noise(rng, size, cells):
    """Bruit lisse : une grille aléatoire agrandie par interpolation bilinéaire."""
    grid = rng.random((cells + 1, cells + 1))
    coords = np.linspace(0, cells, size, endpoint=False)
    i = coords.astype(int)
    f = coords - i
    f = f * f * (3 - 2 * f)
    top = grid[i][:, i] * (1 - f)[None, :] + grid[i][:, i + 1] * f[None, :]
    bottom = grid[i + 1][:, i] * (1 - f)[None, :] + grid[i + 1][:, i + 1] * f[None, :]
    return top * (1 - f)[:, None] + bottom * f[:, None]


def _fractal_noise(rng, size, octaves=(4, 8, 16, 32)):
    total = np.zeros((size, size))
    weight = 1.0
    norm = 0.0
    for cells in octaves:
        total += _value_noise(rng, size, cells) * weight
        norm += weight
        weight *= 0.5
    return total / norm


def _rgba(color, alpha=1.0):
    return np.array([*color, alpha], dtype=np.float32)


def _paint(image, mask, color, opacity=1.0):
    mask = np.clip(mask * opacity, 0, 1)[..., None]
    image[..., :3] = image[..., :3] * (1 - mask) + np.array(color)[None, None, :] * mask


def _disc(size, cx, cy, radius):
    y, x = np.mgrid[0:size, 0:size]
    return ((x - cx) ** 2 + (y - cy) ** 2) <= radius**2


def metal_panels(seed=1):
    """Tôle bleu ardoise façon décor d'anime : aplats, joints nets, liseré clair en haut de chaque
    panneau et léger dégradé peint. La texture couvre 2 m de mur."""
    rng = _rng(seed)
    image = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    image[..., 3] = 1.0
    base = np.array([0.2, 0.22, 0.42])
    gradient = np.linspace(0.8, 1.1, SIZE)[:, None, None]
    image[..., :3] = base[None, None, :] * gradient

    panel = SIZE // 4
    for py in range(4):
        for px in range(4):
            shade = 0.92 + 0.16 * rng.random()
            image[py * panel:(py + 1) * panel, px * panel:(px + 1) * panel, :3] *= shade

    # Quelques panneaux techniques : un aplat plus clair avec une grille d'aération.
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    for _ in range(3):
        px, py = rng.integers(0, 4, 2)
        inside = ((x // panel == px) & (y // panel == py) & (x % panel > 20) & (x % panel < panel - 20)
                  & (y % panel > 30) & (y % panel < panel - 30))
        _paint(image, inside.astype(float), (0.3, 0.33, 0.58))
        _paint(image, (inside & ((y % 10) < 3)).astype(float), (0.1, 0.1, 0.24))

    seam = np.zeros((SIZE, SIZE))
    for k in range(0, SIZE + 1, panel):
        seam[max(k - 2, 0):k + 2, :] = 1
        seam[:, max(k - 2, 0):k + 2] = 1
    highlight = np.roll(seam, -4, axis=0) * (1 - seam)
    _paint(image, highlight, (0.45, 0.5, 0.8), 0.6)
    _paint(image, seam, (0.06, 0.05, 0.16))

    for py in range(4):
        for px in range(4):
            for ox, oy in ((12, 12), (panel - 12, 12), (12, panel - 12), (panel - 12, panel - 12)):
                mask = _disc(SIZE, px * panel + ox, py * panel + oy, 3.5)
                _paint(image, mask.astype(float), (0.4, 0.44, 0.72))
    return np.clip(image, 0, 1)


def floor_tiles(seed=2):
    """Grandes dalles d'un mètre, indigo moyen, joints fins et quelques variations de ton peintes.
    La texture couvre une tuile de 2 m."""
    rng = _rng(seed)
    image = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    image[..., 3] = 1.0
    tile = SIZE // 2
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    image[..., :3] = np.array([0.17, 0.16, 0.33])
    for ty in range(2):
        for tx in range(2):
            shade = 0.95 + 0.1 * rng.random()
            image[ty * tile:(ty + 1) * tile, tx * tile:(tx + 1) * tile, :3] *= shade

    # Taches de ton très douces, comme un fond peint à la main.
    wash = _fractal_noise(rng, SIZE, (3, 6))
    image[..., :3] *= (0.94 + 0.12 * wash)[..., None]

    local_x, local_y = x % tile, y % tile
    seam = (local_x < 2) | (local_x > tile - 3) | (local_y < 2) | (local_y > tile - 3)
    _paint(image, seam.astype(float), (0.09, 0.08, 0.2))
    return np.clip(image, 0, 1)


def grating(seed=3):
    """Caillebotis de couloir : fentes sombres dans une tôle. Couvre une tuile de 2 m."""
    rng = _rng(seed)
    image = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    image[..., 3] = 1.0
    grime = _fractal_noise(rng, SIZE)
    image[..., :3] = np.array([0.18, 0.18, 0.32])[None, None, :] * (0.85 + 0.3 * grime[..., None])
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    slots = ((x % 32) > 4) & ((x % 32) < 28) & ((y % 12) > 3) & ((y % 12) < 9)
    _paint(image, slots.astype(float), (0.04, 0.03, 0.1))
    border = (x < 10) | (x > SIZE - 11) | (y < 10) | (y > SIZE - 11)
    _paint(image, border.astype(float), (0.32, 0.33, 0.55))
    return np.clip(image, 0, 1)


def screen(seed, tint):
    """Écran d'interface : barre de titre, lignes de faux texte, courbe et cadre. Émissif."""
    rng = _rng(seed)
    size = 256
    image = np.zeros((size, size, 4), dtype=np.float32)
    image[..., 3] = 1.0
    tint = np.array(tint)
    image[..., :3] = tint * 0.04
    y, x = np.mgrid[0:size, 0:size]
    lit = np.zeros((size, size))
    lit[(x < 6) | (x > size - 7) | (y < 6) | (y > size - 7)] = 1
    lit[size - 34:size - 14, 14:size - 14] = 0.9
    row = size - 50
    while row > 30:
        col = 16
        while col < size - 30:
            word = rng.integers(6, 30)
            if rng.random() < 0.8:
                lit[row - 6:row, col:min(col + word, size - 16)] = 0.55 + 0.45 * rng.random()
            col += word + rng.integers(4, 10)
        row -= rng.integers(12, 18)
    # Petite courbe dans le coin bas droit.
    for i in range(80):
        px = size - 110 + i
        py = int(40 + 18 * np.sin(i * 0.25) + rng.normal(0, 2))
        lit[py - 1:py + 2, px:px + 2] = 1
    scanlines = 0.8 + 0.2 * ((y // 2) % 2)
    image[..., :3] += tint[None, None, :] * (lit * scanlines)[..., None]
    return np.clip(image, 0, 1)


def crate(seed=4):
    """Caisse orange : planches, bandes sombres, pochoir et éraflures."""
    rng = _rng(seed)
    size = 256
    image = np.zeros((size, size, 4), dtype=np.float32)
    image[..., 3] = 1.0
    grime = _fractal_noise(rng, size, (4, 8, 16))
    image[..., :3] = np.array([0.85, 0.32, 0.06])[None, None, :] * (0.85 + 0.25 * grime[..., None])
    y, x = np.mgrid[0:size, 0:size]
    _paint(image, ((x < 18) | (x > size - 19) | (y < 18) | (y > size - 19)).astype(float), (0.35, 0.1, 0.05))
    _paint(image, (abs(x - y) < 9).astype(float), (0.35, 0.1, 0.05), 0.9)
    _paint(image, ((y % 64) < 2).astype(float), (0.5, 0.16, 0.04))
    stencil = (x > 150) & (x < 220) & (y > 34) & (y < 54) & ((x // 9) % 2 == 0)
    _paint(image, stencil.astype(float), (0.95, 0.9, 0.8), 0.9)
    return np.clip(image, 0, 1)


def hazard(seed=5):
    """Bandes de danger jaunes et noires en diagonale, usées."""
    rng = _rng(seed)
    size = 256
    image = np.zeros((size, size, 4), dtype=np.float32)
    image[..., 3] = 1.0
    y, x = np.mgrid[0:size, 0:size]
    stripes = ((x + y) // 32) % 2 == 0
    image[..., :3] = np.where(stripes[..., None], [0.95, 0.72, 0.05], [0.06, 0.05, 0.12])
    wear = _fractal_noise(rng, size, (8, 16, 32)) > 0.68
    _paint(image, wear.astype(float), (0.3, 0.28, 0.3), 0.4)
    return np.clip(image, 0, 1)
