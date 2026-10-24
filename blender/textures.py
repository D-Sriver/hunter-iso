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
    """Tôle vert-gris en panneaux de 50 cm : joints, rivets, usure et coulures de rouille.
    La texture couvre 2 m de mur."""
    rng = _rng(seed)
    image = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    image[..., 3] = 1.0
    base = np.array([0.075, 0.1, 0.1])
    grime = _fractal_noise(rng, SIZE)
    image[..., :3] = base[None, None, :] * (0.7 + 0.6 * grime[..., None])

    # Chaque panneau a une teinte légèrement différente.
    panel = SIZE // 4
    for py in range(4):
        for px in range(4):
            shade = 0.85 + 0.3 * rng.random()
            image[py * panel:(py + 1) * panel, px * panel:(px + 1) * panel, :3] *= shade

    # Rouille : taches rouge-brun là où le bruit est fort, plus fréquentes en bas.
    rust = _fractal_noise(rng, SIZE, (6, 12, 24))
    height_bias = np.linspace(0.18, 0.0, SIZE)[:, None]
    _paint(image, (rust + height_bias > 0.72).astype(float), (0.16, 0.05, 0.035), 0.4)

    # Coulures verticales sous les joints horizontaux.
    for _ in range(40):
        x = rng.integers(0, SIZE)
        top = (rng.integers(1, 4) * panel) - 2
        length = rng.integers(20, 90)
        image[max(top - length, 0):top, x:x + 2, :3] *= 0.75

    # Joints entre panneaux.
    seam = np.zeros((SIZE, SIZE))
    for k in range(0, SIZE + 1, panel):
        seam[max(k - 2, 0):k + 2, :] = 1
        seam[:, max(k - 2, 0):k + 2] = 1
    _paint(image, seam, (0.02, 0.025, 0.03))
    highlight = np.roll(seam, 3, axis=0) * (1 - seam)
    _paint(image, highlight, (0.2, 0.24, 0.24), 0.35)

    # Rivets aux coins des panneaux.
    for py in range(4):
        for px in range(4):
            for ox, oy in ((10, 10), (panel - 10, 10), (10, panel - 10), (panel - 10, panel - 10)):
                mask = _disc(SIZE, px * panel + ox, py * panel + oy, 3.2)
                _paint(image, mask.astype(float), (0.22, 0.25, 0.25))

    # Rayures claires.
    for _ in range(60):
        x0, y0 = rng.integers(0, SIZE, 2)
        length = rng.integers(8, 40)
        angle = rng.uniform(-0.4, 0.4)
        for t in range(length):
            x = int(x0 + t * np.cos(angle)) % SIZE
            y = int(y0 + t * np.sin(angle)) % SIZE
            image[y, x, :3] = np.minimum(image[y, x, :3] + 0.08, 1)
    return np.clip(image, 0, 1)


def circuit_floor(seed=2):
    """Dalles sombres parcourues de pistes de circuit. Rend (couleur, émission).
    La texture couvre une tuile de 2 m."""
    rng = _rng(seed)
    color = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    color[..., 3] = 1.0
    grime = _fractal_noise(rng, SIZE)
    color[..., :3] = np.array([0.03, 0.04, 0.042])[None, None, :] * (0.7 + 0.6 * grime[..., None])

    trace = np.zeros((SIZE, SIZE))
    cell = 16
    cells = SIZE // cell
    occupied = np.zeros((cells, cells), dtype=bool)
    for _ in range(12):
        cx, cy = rng.integers(1, cells - 1, 2)
        if occupied[cy, cx]:
            continue
        direction = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.integers(0, 4)]
        path = [(cx, cy)]
        for _ in range(rng.integers(6, 22)):
            if rng.random() < 0.25:
                dx, dy = direction
                direction = [(dy, dx), (-dy, -dx)][rng.integers(0, 2)]
            nx, ny = path[-1][0] + direction[0], path[-1][1] + direction[1]
            if not (0 < nx < cells - 1 and 0 < ny < cells - 1) or occupied[ny, nx]:
                break
            path.append((nx, ny))
        if len(path) < 4:
            continue
        for (ax, ay), (bx, by) in zip(path, path[1:]):
            occupied[ay, ax] = True
            x0, x1 = sorted((ax * cell + cell // 2, bx * cell + cell // 2))
            y0, y1 = sorted((ay * cell + cell // 2, by * cell + cell // 2))
            trace[y0 - 1:y1 + 2, x0 - 1:x1 + 2] = 1
        occupied[path[-1][1], path[-1][0]] = True
        for end in (path[0], path[-1]):
            ex, ey = end[0] * cell + cell // 2, end[1] * cell + cell // 2
            trace = np.maximum(trace, _disc(SIZE, ex, ey, 5).astype(float))
            trace[_disc(SIZE, ex, ey, 2)] = 0.3

    # Joints des quatre dalles.
    seam = np.zeros((SIZE, SIZE))
    half = SIZE // 2
    for k in (0, half, SIZE - 1):
        seam[max(k - 2, 0):k + 3, :] = 1
        seam[:, max(k - 2, 0):k + 3] = 1

    teal = np.array([0.1, 1.0, 0.75])
    _paint(color, trace, teal * 0.35)
    _paint(color, seam, (0.008, 0.01, 0.012))
    emission = np.zeros_like(color)
    emission[..., 3] = 1.0
    emission[..., :3] = teal[None, None, :] * trace[..., None] * (1 - seam[..., None])
    return np.clip(color, 0, 1), np.clip(emission, 0, 1)


def grating(seed=3):
    """Caillebotis de couloir : fentes sombres dans une tôle. Couvre une tuile de 2 m."""
    rng = _rng(seed)
    image = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    image[..., 3] = 1.0
    grime = _fractal_noise(rng, SIZE)
    image[..., :3] = np.array([0.07, 0.08, 0.085])[None, None, :] * (0.6 + 0.8 * grime[..., None])
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    slots = ((x % 32) > 4) & ((x % 32) < 28) & ((y % 12) > 3) & ((y % 12) < 9)
    _paint(image, slots.astype(float), (0.005, 0.006, 0.008))
    border = (x < 10) | (x > SIZE - 11) | (y < 10) | (y > SIZE - 11)
    _paint(image, border.astype(float), (0.11, 0.12, 0.12))
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
    image[..., :3] = np.array([0.42, 0.12, 0.03])[None, None, :] * (0.65 + 0.6 * grime[..., None])
    y, x = np.mgrid[0:size, 0:size]
    _paint(image, ((x < 18) | (x > size - 19) | (y < 18) | (y > size - 19)).astype(float), (0.05, 0.04, 0.035))
    _paint(image, (abs(x - y) < 9).astype(float), (0.05, 0.04, 0.035), 0.9)
    _paint(image, ((y % 64) < 2).astype(float), (0.12, 0.04, 0.01))
    stencil = (x > 150) & (x < 220) & (y > 34) & (y < 54) & ((x // 9) % 2 == 0)
    _paint(image, stencil.astype(float), (0.75, 0.7, 0.6), 0.8)
    return np.clip(image, 0, 1)


def hazard(seed=5):
    """Bandes de danger jaunes et noires en diagonale, usées."""
    rng = _rng(seed)
    size = 256
    image = np.zeros((size, size, 4), dtype=np.float32)
    image[..., 3] = 1.0
    y, x = np.mgrid[0:size, 0:size]
    stripes = ((x + y) // 32) % 2 == 0
    image[..., :3] = np.where(stripes[..., None], [0.7, 0.45, 0.02], [0.02, 0.02, 0.02])
    wear = _fractal_noise(rng, size, (8, 16, 32)) > 0.68
    _paint(image, wear.astype(float), (0.08, 0.08, 0.08), 0.8)
    return np.clip(image, 0, 1)
