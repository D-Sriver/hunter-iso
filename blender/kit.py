"""Kit modulaire de Hunter Iso : modélise chaque pièce dans Blender et l'exporte en .glb pour Godot.

Depuis la racine du dépôt :
    blender --background --python blender/kit.py
    blender --background --python blender/kit.py -- --preview   (rend aussi une salle d'exemple)

Conventions (repère Blender, Z vers le haut) :
- une tuile fait 2 m ; les sols sont centrés sur l'origine, dessus à z = 0 ;
- les murs courent le long de X, centrés sur l'origine, épaisseur sur Y, de z = 0 à 3 m ;
- l'avant des meubles regarde vers -Y.
"""

import math
import os
import sys

import bpy  # noqa: I001 (bpy doit être importé avant bmesh hors de Blender)
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import textures  # noqa: E402

ROOT = os.path.dirname(HERE)
KIT_DIR = os.path.join(ROOT, "assets", "kit")
TEXTURE_DIR = os.path.join(KIT_DIR, "textures")

TILE = 2.0
WALL_HEIGHT = 3.0
WALL_THICKNESS = 0.3
STUB_HEIGHT = 0.5

NEON_PINK = (1.0, 0.12, 0.5)
NEON_TEAL = (0.1, 1.0, 0.75)
NEON_GREEN = (0.25, 1.0, 0.35)
NEON_GOLD = (1.0, 0.65, 0.1)

KIT = bpy.data.collections.new("Kit") if False else None
MATERIALS = {}


# --- Scène et matériaux -------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global KIT
    KIT = bpy.data.collections.new("Kit")
    bpy.context.scene.collection.children.link(KIT)


def image_from_array(name, array):
    """Enregistre un tableau linéaire en PNG (encodé sRGB) et le charge comme image Blender."""
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    height, width = array.shape[:2]
    encoded = array.copy()
    encoded[..., :3] = encoded[..., :3] ** (1 / 2.2)
    image = bpy.data.images.new(name, width, height, alpha=False)
    image.pixels.foreach_set(encoded.ravel())
    image.filepath_raw = os.path.join(TEXTURE_DIR, name + ".png")
    image.file_format = "PNG"
    image.save()
    return image


def material(name, color=(0.1, 0.1, 0.1), metallic=0.3, roughness=0.6, emission=None,
             strength=0.0, texture=None, emission_texture=None):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if texture is not None:
        node = nodes.new("ShaderNodeTexImage")
        node.image = texture
        links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if emission_texture is not None:
        node = nodes.new("ShaderNodeTexImage")
        node.image = emission_texture
        links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = strength
    MATERIALS[name] = mat
    return mat


def build_materials():
    metal = image_from_array("metal_panels", textures.metal_panels())
    screen_teal = image_from_array("screen_teal", textures.screen(7, NEON_TEAL))
    screen_pink = image_from_array("screen_pink", textures.screen(8, NEON_PINK))
    material("metal", metallic=0.3, roughness=0.55, texture=metal)
    material("metal_dark", color=(0.09, 0.08, 0.2), metallic=0.3, roughness=0.5)
    material("trim_light", color=(0.55, 0.58, 0.85), metallic=0.3, roughness=0.5)
    material("copper", color=(0.85, 0.4, 0.15), metallic=0.6, roughness=0.35)
    material("rubber", color=(0.05, 0.04, 0.1), metallic=0.0, roughness=0.8)
    material("skin", color=(0.95, 0.72, 0.6), metallic=0.0, roughness=0.6)
    for name, color in (("coat_red", (0.8, 0.1, 0.12)), ("coat_purple", (0.4, 0.15, 0.6)),
                        ("coat_mustard", (0.85, 0.6, 0.12))):
        material(name, color=color, metallic=0.0, roughness=0.5)
    material("floor_tiles", metallic=0.1, roughness=0.3,
             texture=image_from_array("floor_tiles", textures.floor_tiles()))
    material("grating", metallic=0.3, roughness=0.5,
             texture=image_from_array("grating", textures.grating()))
    material("crate", metallic=0.1, roughness=0.7,
             texture=image_from_array("crate", textures.crate()))
    material("hazard", metallic=0.2, roughness=0.6,
             texture=image_from_array("hazard", textures.hazard()))
    material("screen_teal", texture=screen_teal, emission_texture=screen_teal, strength=2.5)
    material("screen_pink", texture=screen_pink, emission_texture=screen_pink, strength=2.5)
    for name, color in (("neon_pink", NEON_PINK), ("neon_teal", NEON_TEAL),
                        ("neon_green", NEON_GREEN), ("neon_gold", NEON_GOLD)):
        material(name, color=color, emission=color, strength=6.0)
    material("relic", color=NEON_TEAL, metallic=0.2, roughness=0.1, emission=NEON_TEAL, strength=3.0)


# --- Géométrie ----------------------------------------------------------------------------------

def project_uv(bm, mode, scale):
    """Projection cubique : chaque face prend l'axe de sa normale.
    mode "world" : la texture couvre `scale` mètres ; mode "face" : la texture remplit la face."""
    uv_layer = bm.loops.layers.uv.verify()
    bm.normal_update()
    for face in bm.faces:
        axis = max(range(3), key=lambda i: abs(face.normal[i]))
        coords = []
        for loop in face.loops:
            co = loop.vert.co
            coords.append((co.y, co.z) if axis == 0 else (co.x, co.z) if axis == 1 else (co.x, co.y))
        if mode == "face":
            min_u = min(c[0] for c in coords)
            min_v = min(c[1] for c in coords)
            span_u = max(max(c[0] for c in coords) - min_u, 1e-6)
            span_v = max(max(c[1] for c in coords) - min_v, 1e-6)
            coords = [((u - min_u) / span_u, (v - min_v) / span_v) for u, v in coords]
        else:
            coords = [(u / scale + 0.5, v / scale) for u, v in coords]
        for loop, uv in zip(face.loops, coords):
            loop[uv_layer].uv = uv


def finish(bm, mat, uv="world", uv_scale=2.0):
    project_uv(bm, uv, uv_scale)
    mesh = bpy.data.meshes.new("part")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(MATERIALS[mat])
    obj = bpy.data.objects.new("part", mesh)
    KIT.objects.link(obj)
    return obj


def transform(bm, center, rotation):
    rx, ry, rz = rotation
    matrix = Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)


def box(size, center, mat, bevel=0.0, rotation=(0.0, 0.0, 0.0), uv="world", uv_scale=2.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
    transform(bm, center, rotation)
    return finish(bm, mat, uv, uv_scale)


def cylinder(radius, depth, center, mat, rotation=(0.0, 0.0, 0.0), segments=16, top_radius=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if top_radius is None else top_radius, depth=depth)
    transform(bm, center, rotation)
    return finish(bm, mat, "world", 1.0)


def neon_text(text, size, center, mat, facing):
    """Texte néon en relief. `facing` : -1 pour regarder vers -Y, +1 vers +Y."""
    curve = bpy.data.curves.new("text", "FONT")
    curve.body = text
    curve.size = size
    curve.extrude = 0.015
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    source = bpy.data.objects.new("text", curve)
    KIT.objects.link(source)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph))
    bpy.data.objects.remove(source)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    transform(bm, center, (math.pi / 2, 0.0, 0.0 if facing < 0 else math.pi))
    return finish(bm, mat)


def join(name, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = parts[0]
    obj.name = name
    obj.data.name = name
    return obj


def both_faces(build):
    """Applique un détail sur les deux faces d'un mur : build(signe) avec signe = -1 puis +1."""
    parts = []
    for side in (-1, 1):
        parts += build(side)
    return parts


# --- Sols ---------------------------------------------------------------------------------------

def floor_tile(name, mat):
    return join(name, [box((TILE, TILE, 0.1), (0, 0, -0.05), mat)])


# --- Murs ---------------------------------------------------------------------------------------

def wall_shell(width=TILE):
    half = WALL_THICKNESS / 2
    parts = [
        box((width, WALL_THICKNESS, WALL_HEIGHT), (0, 0, WALL_HEIGHT / 2), "metal"),
        box((width, WALL_THICKNESS + 0.08, 0.25), (0, 0, 0.125), "metal_dark", bevel=0.015),
        box((width, WALL_THICKNESS + 0.12, 0.18), (0, 0, WALL_HEIGHT - 0.09), "metal_dark",
            bevel=0.015),
    ]
    for x in (-width / 2 + 0.06, width / 2 - 0.06):
        parts.append(box((0.12, WALL_THICKNESS + 0.1, WALL_HEIGHT), (x, 0, WALL_HEIGHT / 2),
                         "metal_dark", bevel=0.015))
    parts += both_faces(lambda side: [
        box((width - 0.2, 0.03, 0.04), (0, side * (half + 0.015), WALL_HEIGHT - 0.3), "neon_teal"),
    ])
    return parts


def wall_panel():
    parts = wall_shell()
    parts.append(box((1.76, WALL_THICKNESS + 0.04, 0.06), (0, 0, 1.2), "metal_dark"))
    return join("wall_panel", parts)


def wall_screens():
    half = WALL_THICKNESS / 2

    def screen(side):
        mat = "screen_teal" if side < 0 else "screen_pink"
        return [
            box((1.0, 0.06, 0.66), (0, side * (half + 0.03), 1.55), "metal_dark", bevel=0.01),
            box((0.9, 0.01, 0.56), (0, side * (half + 0.065), 1.55), mat, uv="face"),
            box((0.3, 0.05, 0.3), (-0.62, side * (half + 0.025), 1.3), "metal_dark", bevel=0.01),
            box((0.24, 0.01, 0.2), (-0.62, side * (half + 0.055), 1.3), mat, uv="face"),
        ]

    return join("wall_screens", wall_shell() + both_faces(screen))


def wall_pipes():
    half = WALL_THICKNESS / 2

    def pipes(side):
        y = side * (half + 0.09)
        parts = [
            cylinder(0.06, TILE, (0, y, 0.6), "metal_dark", rotation=(0, math.pi / 2, 0)),
            cylinder(0.045, TILE, (0, y + side * 0.02, 0.78), "copper",
                     rotation=(0, math.pi / 2, 0)),
            cylinder(0.08, TILE, (0, y, 2.35), "metal_dark", rotation=(0, math.pi / 2, 0)),
        ]
        for x in (-0.6, 0.6):
            parts.append(box((0.06, 0.18, 0.4), (x, side * (half + 0.06), 0.68), "metal_dark"))
            parts.append(box((0.06, 0.18, 0.18), (x, side * (half + 0.06), 2.35), "metal_dark"))
        parts.append(box((0.5, 0.05, 0.35), (0.35, side * (half + 0.025), 1.5), "grating",
                         uv="face"))
        return parts

    return join("wall_pipes", wall_shell() + both_faces(pipes))


def wall_neon(name, text, mat):
    half = WALL_THICKNESS / 2

    def sign(side):
        return [
            box((1.5, 0.04, 0.5), (0, side * (half + 0.02), 1.9), "metal_dark", bevel=0.01),
            neon_text(text, 0.34, (0, side * (half + 0.05), 1.9), mat, side),
        ]

    return join(name, wall_shell() + both_faces(sign))


def wall_door():
    """Mur percé d'une porte de 1,3 m, encadrée de bandes de danger et d'un néon vert."""
    opening = 1.3
    side_width = (TILE - opening) / 2
    half = WALL_THICKNESS / 2
    parts = []
    for direction in (-1, 1):
        x = direction * (TILE / 2 - side_width / 2)
        parts += [
            box((side_width, WALL_THICKNESS, WALL_HEIGHT), (x, 0, WALL_HEIGHT / 2), "metal"),
            box((side_width, WALL_THICKNESS + 0.08, 0.25), (x, 0, 0.125), "metal_dark"),
            box((0.07, WALL_THICKNESS + 0.06, 2.4), (direction * opening / 2, 0, 1.2), "hazard",
                uv="face"),
        ]
    parts += [
        box((TILE, WALL_THICKNESS, 0.6), (0, 0, WALL_HEIGHT - 0.3), "metal"),
        box((opening, WALL_THICKNESS + 0.06, 0.07), (0, 0, 2.4), "hazard", uv="face"),
        box((TILE, WALL_THICKNESS + 0.12, 0.18), (0, 0, WALL_HEIGHT - 0.09), "metal_dark"),
    ]
    parts += both_faces(lambda side: [
        box((opening - 0.2, 0.03, 0.05), (0, side * (half + 0.03), 2.55), "neon_green"),
    ])
    return join("wall_door", parts)


def wall_stub():
    """Muret à garde-corps : remplace les murs entre la caméra et le joueur."""
    parts = [
        box((TILE, WALL_THICKNESS, STUB_HEIGHT), (0, 0, STUB_HEIGHT / 2), "metal"),
        box((TILE, WALL_THICKNESS + 0.06, 0.06), (0, 0, STUB_HEIGHT + 0.03), "metal_dark"),
        cylinder(0.03, TILE, (0, 0, 1.05), "metal_dark", rotation=(0, math.pi / 2, 0)),
        cylinder(0.02, TILE, (0, 0, 0.8), "metal_dark", rotation=(0, math.pi / 2, 0)),
    ]
    for x in (-0.9, 0.0, 0.9):
        parts.append(cylinder(0.025, 0.5, (x, 0, STUB_HEIGHT + 0.3), "metal_dark"))
    return join("wall_stub", parts)


def wall_post():
    """Poteau d'angle, posé aux coins pour cacher les jonctions entre murs."""
    return join("wall_post", [
        box((0.42, 0.42, WALL_HEIGHT), (0, 0, WALL_HEIGHT / 2), "metal_dark", bevel=0.03),
        box((0.46, 0.46, 0.05), (0, 0, WALL_HEIGHT - 0.3), "neon_teal"),
    ])


# --- Mobilier -----------------------------------------------------------------------------------

def server_rack(seed=11):
    """Baie serveur de 2,2 m : cache un hunter. Diodes sur les deux faces."""
    import random
    rng = random.Random(seed)
    parts = [
        box((0.9, 1.0, 2.2), (0, 0, 1.1), "metal_dark", bevel=0.02),
        box((0.8, 0.02, 2.0), (0, -0.505, 1.1), "grating", uv="face"),
        box((0.8, 0.02, 2.0), (0, 0.505, 1.1), "grating", uv="face"),
        cylinder(0.05, 1.0, (-0.2, 0, 2.25), "rubber", rotation=(math.pi / 2, 0, 0)),
        cylinder(0.04, 1.0, (0.1, 0, 2.24), "rubber", rotation=(math.pi / 2, 0, 0)),
    ]
    for side in (-1, 1):
        for row in range(12):
            for column in range(5):
                if rng.random() < 0.45:
                    continue
                mat = rng.choice(["neon_teal", "neon_teal", "neon_green", "neon_pink"])
                parts.append(box((0.04, 0.01, 0.025),
                                 (-0.3 + column * 0.15, side * 0.52, 0.3 + row * 0.15), mat))
    return join("server_rack", parts)


def crate():
    return join("crate", [box((0.8, 0.8, 0.8), (0, 0, 0.4), "crate", bevel=0.03, uv="face")])


def crate_stack():
    return join("crate_stack", [
        box((0.8, 0.8, 0.8), (-0.42, 0, 0.4), "crate", bevel=0.03, uv="face"),
        box((0.8, 0.8, 0.8), (0.42, 0.05, 0.4), "crate", bevel=0.03, uv="face",
            rotation=(0, 0, 0.12)),
        box((0.7, 0.7, 0.7), (0.0, 0.0, 1.15), "crate", bevel=0.03, uv="face",
            rotation=(0, 0, -0.25)),
    ])


def terminal():
    return join("terminal", [
        box((0.6, 0.5, 1.0), (0, 0, 0.5), "metal_dark", bevel=0.03),
        box((0.62, 0.14, 0.46), (0, -0.12, 1.25), "metal_dark", bevel=0.02),
        box((0.52, 0.01, 0.36), (0, -0.195, 1.25), "screen_teal", uv="face"),
        box((0.5, 0.25, 0.04), (0, -0.33, 0.95), "metal_dark"),
        box((0.6, 0.02, 0.03), (0, -0.255, 0.2), "neon_teal"),
    ])


def desk():
    parts = [
        box((1.6, 0.8, 0.06), (0, 0, 0.76), "metal_dark", bevel=0.01),
        box((0.66, 0.05, 0.4), (-0.3, 0.2, 1.1), "metal_dark", bevel=0.01),
        box((0.6, 0.01, 0.34), (-0.3, 0.17, 1.1), "screen_pink", uv="face"),
        box((0.4, 0.05, 0.3), (0.42, 0.22, 1.02), "metal_dark", bevel=0.01),
        box((0.34, 0.01, 0.24), (0.42, 0.19, 1.02), "screen_teal", uv="face"),
        box((0.06, 0.06, 0.2), (-0.3, 0.22, 0.88), "metal_dark"),
        box((0.5, 0.18, 0.03), (-0.2, -0.15, 0.8), "rubber"),
    ]
    for x in (-0.74, 0.74):
        for y in (-0.34, 0.34):
            parts.append(box((0.06, 0.06, 0.73), (x, y, 0.365), "metal_dark"))
    return join("desk", parts)


def lab_table():
    parts = [
        box((1.6, 1.0, 0.86), (0, 0, 0.43), "metal", bevel=0.02),
        box((1.8, 1.2, 0.08), (0, 0, 0.9), "metal_dark", bevel=0.02),
        cylinder(0.22, 0.06, (0.3, 0, 0.97), "metal_dark"),
        box((0.3, 0.2, 0.25), (-0.5, 0.25, 1.06), "metal_dark", bevel=0.01),
        box((1.6, 0.02, 0.03), (0, -0.61, 0.9), "neon_teal"),
    ]
    # Hologramme : anneaux lumineux empilés au-dessus du projecteur.
    for i, radius in enumerate((0.3, 0.24, 0.17, 0.1)):
        parts.append(cylinder(radius, 0.012, (0.3, 0, 1.12 + i * 0.14), "neon_teal", segments=24))
    return join("lab_table", parts)


def pillar():
    return join("pillar", [
        box((0.9, 0.9, 0.3), (0, 0, 0.15), "metal_dark", bevel=0.03),
        box((0.7, 0.7, WALL_HEIGHT), (0, 0, WALL_HEIGHT / 2), "metal", bevel=0.04),
        box((0.74, 0.74, 0.06), (0, 0, 2.2), "neon_pink"),
        box((0.74, 0.74, 0.06), (0, 0, 0.6), "neon_pink"),
    ])


def pedestal():
    return join("pedestal", [
        cylinder(0.75, 0.25, (0, 0, 0.125), "metal_dark", segments=8),
        cylinder(0.5, 0.5, (0, 0, 0.5), "metal", segments=8),
        cylinder(0.53, 0.04, (0, 0, 0.77), "neon_teal", segments=8),
    ])


def relic():
    """Cristal en double pyramide, centré sur l'origine."""
    return join("relic", [
        cylinder(0.25, 0.35, (0, 0, 0.175), "relic", segments=4, top_radius=0.0),
        cylinder(0.25, 0.35, (0, 0, -0.175), "relic", segments=4, top_radius=0.0,
                 rotation=(math.pi, 0, 0)),
    ])


def exit_pad():
    parts = [box((1.8, 1.8, 0.06), (0, 0, 0.03), "metal_dark")]
    for x, y, sx, sy in ((0, -0.8, 1.8, 0.2), (0, 0.8, 1.8, 0.2), (-0.8, 0, 0.2, 1.4),
                         (0.8, 0, 0.2, 1.4)):
        parts.append(box((sx, sy, 0.065), (x, y, 0.035), "hazard", uv="face"))
    parts.append(cylinder(0.5, 0.02, (0, 0, 0.07), "neon_green", segments=32))
    parts.append(cylinder(0.4, 0.025, (0, 0, 0.07), "metal_dark", segments=32))
    return join("exit_pad", parts)


def loot_chest():
    return join("loot_chest", [
        box((0.9, 0.55, 0.45), (0, 0, 0.225), "metal_dark", bevel=0.03),
        box((0.94, 0.59, 0.12), (0, 0, 0.51), "metal", bevel=0.02),
        box((0.92, 0.02, 0.04), (0, -0.285, 0.36), "neon_gold"),
        box((0.12, 0.03, 0.12), (0, -0.29, 0.45), "neon_gold"),
    ])


def barrel():
    return join("barrel", [
        cylinder(0.3, 0.9, (0, 0, 0.45), "metal", segments=20),
        cylinder(0.31, 0.05, (0, 0, 0.2), "metal_dark", segments=20),
        cylinder(0.31, 0.05, (0, 0, 0.7), "metal_dark", segments=20),
        cylinder(0.12, 0.02, (0.1, 0.05, 0.91), "neon_gold", segments=12),
    ])


# --- Hunters ------------------------------------------------------------------------------------

def hunter(name, accent, coat):
    """Hunter stylisé, environ 1,75 m : long manteau, épaulettes, visière lumineuse.
    L'avant regarde vers -Y."""
    parts = [
        box((0.16, 0.18, 0.8), (-0.12, 0, 0.4), "rubber", bevel=0.02),
        box((0.16, 0.18, 0.8), (0.12, 0, 0.4), "rubber", bevel=0.02),
        box((0.2, 0.26, 0.1), (-0.12, -0.03, 0.05), coat, bevel=0.02),
        box((0.2, 0.26, 0.1), (0.12, -0.03, 0.05), coat, bevel=0.02),
        # Pan du manteau : plus large en bas.
        cylinder(0.3, 0.6, (0, 0.02, 0.62), coat, segments=8, top_radius=0.22),
        box((0.46, 0.28, 0.55), (0, 0, 1.18), coat, bevel=0.04),
        box((0.2, 0.3, 0.12), (-0.3, 0, 1.42), "trim_light", bevel=0.03),
        box((0.2, 0.3, 0.12), (0.3, 0, 1.42), "trim_light", bevel=0.03),
        box((0.12, 0.14, 0.55), (-0.31, 0, 1.1), coat, bevel=0.02),
        box((0.12, 0.14, 0.55), (0.31, 0, 1.1), coat, bevel=0.02),
        box((0.1, 0.12, 0.12), (-0.31, -0.02, 0.78), "rubber"),
        box((0.1, 0.12, 0.12), (0.31, -0.02, 0.78), "rubber"),
        box((0.12, 0.12, 0.1), (0, 0, 1.5), "rubber"),
        box((0.24, 0.26, 0.26), (0, 0, 1.66), "skin", bevel=0.05),
        box((0.28, 0.3, 0.12), (0, 0.02, 1.8), "rubber", bevel=0.04),
        box((0.28, 0.04, 0.07), (0, -0.14, 1.68), accent),
        box((0.46, 0.02, 0.04), (0, -0.145, 1.25), accent),
        box((0.04, 0.29, 0.04), (-0.25, 0, 1.47), accent),
        box((0.04, 0.29, 0.04), (0.25, 0, 1.47), accent),
    ]
    return join(name, parts)


# --- Export et aperçu ---------------------------------------------------------------------------

def export(obj):
    os.makedirs(KIT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(KIT_DIR, obj.name + ".glb"),
                              export_format="GLB", use_selection=True, export_apply=True)


def build_kit():
    reset_scene()
    build_materials()
    pieces = [
        floor_tile("floor_room", "floor_tiles"),
        floor_tile("floor_corridor", "grating"),
        wall_panel(), wall_screens(), wall_pipes(),
        wall_neon("wall_neon_pink", "NEXUS", "neon_pink"),
        wall_neon("wall_neon_teal", "24H OPEN", "neon_teal"),
        wall_door(), wall_stub(), wall_post(),
        server_rack(), crate(), crate_stack(), terminal(), desk(), lab_table(), pillar(),
        pedestal(), relic(), exit_pad(), loot_chest(), barrel(),
        hunter("hunter_player", "neon_teal", "coat_red"),
        hunter("hunter_rival_purple", "neon_pink", "coat_purple"),
        hunter("hunter_rival_gold", "neon_gold", "coat_mustard"),
    ]
    for piece in pieces:
        export(piece)
    return {piece.name: piece for piece in pieces}


def place(kit, name, location, rotation_z=0.0):
    obj = kit[name].copy()
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, rotation_z)
    return obj


def point_light(location, color, energy, radius=0.2):
    data = bpy.data.lights.new("light", "POINT")
    data.color = color
    data.energy = energy
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new("light", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location


def toonify(mat):
    """Remplace le Principled par un cel-shading à deux tons pour l'aperçu.
    Les ombres restent colorées (couleur × 0,45) au lieu de tomber au noir, comme en anime."""
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    output = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
    color_input = bsdf.inputs["Base Color"]
    color_source = color_input.links[0].from_socket if color_input.links else None

    toon = nodes.new("ShaderNodeBsdfToon")
    toon.component = "DIFFUSE"
    toon.inputs["Size"].default_value = 0.6
    toon.inputs["Smooth"].default_value = 0.03
    ambient = nodes.new("ShaderNodeEmission")
    ambient.inputs["Strength"].default_value = 0.45
    for socket in (toon.inputs["Color"], ambient.inputs["Color"]):
        if color_source is not None:
            links.new(color_source, socket)
        else:
            socket.default_value = color_input.default_value
    shaded = nodes.new("ShaderNodeAddShader")
    links.new(toon.outputs[0], shaded.inputs[0])
    links.new(ambient.outputs[0], shaded.inputs[1])

    glow = nodes.new("ShaderNodeEmission")
    glow.inputs["Strength"].default_value = bsdf.inputs["Emission Strength"].default_value
    emission_input = bsdf.inputs["Emission Color"]
    if emission_input.links:
        links.new(emission_input.links[0].from_socket, glow.inputs["Color"])
    else:
        glow.inputs["Color"].default_value = emission_input.default_value
    total = nodes.new("ShaderNodeAddShader")
    links.new(shaded.outputs[0], total.inputs[0])
    links.new(glow.outputs[0], total.inputs[1])
    links.new(total.outputs[0], output.inputs["Surface"])


def add_bloom(path, threshold=0.8, strength=0.9):
    """Halo autour des néons, ajouté après le rendu (le compositeur exige un GPU)."""
    import numpy as np
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    bright = np.clip(pixels[..., :3] - threshold, 0, None)
    glow = np.zeros_like(bright)
    for radius in (4, 12, 28):
        blurred = bright
        for axis in (0, 1):
            kernel = np.ones(radius * 2 + 1) / (radius * 2 + 1)
            blurred = np.apply_along_axis(lambda line: np.convolve(line, kernel, "same"), axis,
                                          blurred)
        glow += blurred
    pixels[..., :3] = np.clip(pixels[..., :3] + glow * strength, 0, 1)
    image.pixels.foreach_set(pixels.ravel())
    image.save()


def render_preview(kit, path):
    """Salle d'exemple 5 × 4 tuiles vue en iso : murs du fond pleins, muret devant, mobilier."""
    KIT.hide_render = True
    width, depth = 5, 4
    for x in range(width):
        for y in range(depth):
            place(kit, "floor_room", (x * TILE, y * TILE, 0))
        place(kit, "floor_corridor", (x * TILE, -TILE, 0))
    back = ["wall_screens", "wall_neon_pink", "wall_panel", "wall_pipes", "wall_door"]
    for x, name in enumerate(back):
        place(kit, name, (x * TILE, (depth - 0.5) * TILE, 0))
    side = ["wall_pipes", "wall_neon_teal", "wall_screens", "wall_panel"]
    for y, name in enumerate(side):
        place(kit, name, (-TILE / 2, y * TILE, 0), math.pi / 2)
    for x in range(width):
        place(kit, "wall_stub", (x * TILE, -TILE / 2, 0))
    for y in range(depth):
        place(kit, "wall_stub", ((width - 0.5) * TILE, y * TILE, 0), math.pi / 2)
    place(kit, "wall_post", (-TILE / 2, (depth - 0.5) * TILE, 0))

    for y in (2.2, 4.2):
        for x in (0.4, 1.3):
            place(kit, "server_rack", (x, y, 0), math.pi / 2)
    place(kit, "desk", (4.0, 6.5, 0), math.pi)
    place(kit, "terminal", (6.2, 6.6, 0), math.pi)
    place(kit, "lab_table", (5.0, 3.0, 0))
    place(kit, "crate_stack", (8.0, 6.2, 0), 0.3)
    place(kit, "crate", (8.4, 4.6, 0), -0.4)
    place(kit, "barrel", (7.6, 5.0, 0))
    place(kit, "pedestal", (3.4, 0.6, 0))
    place(kit, "relic", (3.4, 0.6, 1.25), 0.4)
    place(kit, "loot_chest", (0.2, 0.2, 0), 0.5)
    place(kit, "exit_pad", (8.0, 0.0, 0))
    place(kit, "hunter_player", (6.0, 1.2, 0), math.radians(-150))
    place(kit, "hunter_rival_purple", (2.4, 4.6, 0), math.radians(30))

    # Lumière de cel-shading : une lune lavande franche, des néons colorés en complément.
    sun_data = bpy.data.lights.new("moon", "SUN")
    sun_data.color = (0.85, 0.82, 1.0)
    sun_data.energy = 3.0
    sun_data.angle = 0.05
    sun = bpy.data.objects.new("moon", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    point_light((1.0, 6.0, 2.4), NEON_PINK, 150)
    point_light((-0.5, 3.0, 2.2), NEON_TEAL, 100)
    point_light((5.0, 3.0, 2.0), NEON_TEAL, 60)
    point_light((8.0, 6.0, 2.4), (1.0, 0.55, 0.2), 120)
    point_light((8.0, 0.0, 1.0), NEON_GREEN, 40)

    for mat in MATERIALS.values():
        toonify(mat)

    scene = bpy.context.scene
    world = bpy.data.worlds.new("World")
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.02, 0.08, 1)
    scene.world = world

    camera_data = bpy.data.cameras.new("Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 15.5
    camera = bpy.data.objects.new("Camera", camera_data)
    scene.collection.objects.link(camera)
    camera.rotation_euler = (math.radians(57), 0, math.radians(45))
    target = Vector((4.0, 3.0, 0.8))
    forward = camera.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    camera.location = target - forward * 40
    scene.camera = camera

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 1000
    scene.view_settings.view_transform = "Standard"
    scene.render.use_freestyle = True
    scene.render.line_thickness = 1.3
    freestyle = scene.view_layers[0].freestyle_settings
    lineset = freestyle.linesets[0] if freestyle.linesets else freestyle.linesets.new("contours")
    if lineset.linestyle is None:
        lineset.linestyle = bpy.data.linestyles.new("contours")
    lineset.select_by_visibility = True
    lineset.select_crease = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.linestyle.color = (0.04, 0.02, 0.1)
    # Pas de contour sur les néons et écrans : ils sont trop fins, le trait les noierait.
    lineset.select_by_face_marks = True
    lineset.face_mark_negation = "EXCLUSIVE"
    lineset.face_mark_condition = "ONE"
    for obj in scene.objects:
        if obj.type != "MESH":
            continue
        # Ni sur les sols : chaque tuile tracerait un quadrillage épais.
        glowing = [slot.material is not None and slot.material.name.startswith(
            ("neon", "screen", "relic", "floor", "grating")) for slot in obj.material_slots]
        mesh = obj.data
        marks = mesh.attributes.get("freestyle_face") or mesh.attributes.new(
            "freestyle_face", "BOOLEAN", "FACE")
        marks.data.foreach_set("value", [glowing[p.material_index] for p in mesh.polygons])
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    add_bloom(path)


if __name__ == "__main__":
    kit_objects = build_kit()
    if "--preview" in sys.argv:
        render_preview(kit_objects, os.path.join(KIT_DIR, "preview.png"))
