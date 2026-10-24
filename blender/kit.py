"""Kit modulaire de Hunter Iso : modélise chaque pièce dans Blender et l'exporte en .glb pour Godot.

Depuis la racine du dépôt :
    blender --background --python blender/kit.py
    blender --background --python blender/kit.py -- --preview   (rend aussi une salle d'exemple)
    blender --background --python blender/kit.py -- --lineup    (rend les six hunters)

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
    image = bpy.data.images.new(name, width, height, alpha=bool((array[..., 3] < 1).any()))
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
        if texture.alpha_mode != "NONE" and texture.depth == 32:
            links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
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
    material("skin", color=(0.88, 0.6, 0.48), metallic=0.0, roughness=0.6)
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


def finish(bm, mat, uv="world", uv_scale=2.0, smooth=False):
    project_uv(bm, uv, uv_scale)
    for face in bm.faces:
        face.smooth = smooth
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
# Personnages façon anime 90's, modelés en volumes lisses : corps et vêtements générés par le
# modificateur Skin (squelette + rayons) puis subdivisés, tête déformée (crâne large, menton
# pointu), yeux peints, cheveux en mèches effilées. Pose en A pour le rig à venir.
# L'avant regarde vers -Y.

HEAD_CENTER = Vector((0.0, 0.0, 1.63))
HEAD_SIZE = Vector((0.105, 0.115, 0.125))

HUNTERS = [
    {"name": "hunter_kaz", "body": "male", "outfit": "trench", "coat": (0.8, 0.1, 0.12),
     "pants": (0.08, 0.07, 0.16), "hair": "spiky", "hair_color": (0.07, 0.06, 0.14),
     "eyes": (0.9, 0.35, 0.1), "accent": "neon_teal", "weapon": "sword"},
    {"name": "hunter_rook", "body": "big", "outfit": "armor", "coat": (0.85, 0.6, 0.12),
     "pants": (0.15, 0.13, 0.22), "hair": "buzz", "hair_color": (0.45, 0.2, 0.08),
     "eyes": (0.35, 0.6, 0.2), "accent": "neon_gold", "weapon": "hammer"},
    {"name": "hunter_vex", "body": "male", "outfit": "trench", "coat": (0.4, 0.15, 0.6),
     "pants": (0.06, 0.05, 0.12), "hair": "swept", "hair_color": (0.85, 0.87, 0.95),
     "eyes": (0.8, 0.1, 0.2), "accent": "neon_pink", "weapon": "rifle"},
    {"name": "hunter_nova", "body": "female", "outfit": "bomber", "coat": (0.78, 0.8, 0.9),
     "pants": (0.1, 0.12, 0.3), "hair": "bob", "hair_color": (1.0, 0.3, 0.6),
     "eyes": (0.1, 0.75, 0.8), "accent": "neon_teal", "weapon": "pistols"},
    {"name": "hunter_sable", "body": "female", "outfit": "trench", "coat": (0.08, 0.3, 0.25),
     "pants": (0.05, 0.05, 0.1), "hair": "ponytail", "hair_color": (0.06, 0.05, 0.1),
     "eyes": (0.95, 0.65, 0.1), "accent": "neon_gold", "weapon": "scythe"},
    {"name": "hunter_mika", "body": "female", "outfit": "bomber", "coat": (0.95, 0.75, 0.1),
     "pants": (0.06, 0.06, 0.14), "hair": "twintails", "hair_color": (0.2, 0.45, 1.0),
     "eyes": (0.25, 0.4, 1.0), "accent": "neon_pink", "weapon": "blades"},
]


def paint(name, color):
    """Matériau mat à couleur unie, créé à la demande."""
    if name not in MATERIALS:
        material(name, color=color, metallic=0.0, roughness=0.55)
    return name


def sphere(size, center, mat, rotation=(0.0, 0.0, 0.0), segments=14):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments * 2 // 3, radius=0.5)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    transform(bm, center, rotation)
    return finish(bm, mat, "world", 1.0, smooth=True)


def limb(start, end, radius_start, radius_end, mat, segments=10, flatten=1.0, caps=True):
    """Tronc de cône lisse tendu entre deux points ; `flatten` écrase la section en profondeur."""
    start, end = Vector(start), Vector(end)
    axis = end - start
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segments,
                          radius1=radius_start, radius2=radius_end, depth=axis.length)
    bmesh.ops.scale(bm, vec=Vector((1.0, flatten, 1.0)), verts=bm.verts)
    rotation = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=rotation, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(start + end) / 2, verts=bm.verts)
    return finish(bm, mat, "world", 1.0, smooth=True)


def evaluated_bmesh(obj):
    """Applique les modificateurs d'un objet et rend le résultat en bmesh (l'objet est supprimé)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    bpy.data.objects.remove(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    return bm


def skin_part(joints, edges, mat, subdivisions=2):
    """Volume organique : `joints` est une liste de (position, rayon x, rayon y)."""
    mesh = bpy.data.meshes.new("skin")
    mesh.from_pydata([joint[0] for joint in joints], edges, [])
    obj = bpy.data.objects.new("skin", mesh)
    KIT.objects.link(obj)
    obj.modifiers.new("skin", "SKIN")
    data = mesh.skin_vertices[0].data
    for vertex, (_, radius_x, radius_y) in zip(data, joints):
        vertex.radius = (radius_x, radius_y)
    data[0].use_root = True
    subsurf = obj.modifiers.new("subsurf", "SUBSURF")
    subsurf.levels = subdivisions
    subsurf.render_levels = subdivisions
    return finish(evaluated_bmesh(obj), mat, "world", 1.0, smooth=True)


def strand(root, control, tip, width, mat, thickness=0.55, sides=6, steps=8):
    """Mèche de cheveux : tube aplati et effilé le long d'une courbe de Bézier."""
    root, control, tip = Vector(root), Vector(control), Vector(tip)
    bm = bmesh.new()
    rings = []
    for i in range(steps + 1):
        t = i / steps
        position = (1 - t) ** 2 * root + 2 * (1 - t) * t * control + t * t * tip
        tangent = (2 * (1 - t) * (control - root) + 2 * t * (tip - control)).normalized()
        radius = width * (1 - t) ** 0.85 + 0.0015
        side = tangent.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = tangent.cross(Vector((1, 0, 0)))
        side.normalize()
        normal = side.cross(tangent).normalized()
        rings.append([bm.verts.new(position + side * math.cos(a) * radius
                                   + normal * math.sin(a) * radius * thickness)
                      for a in (2 * math.pi * k / sides for k in range(sides))])
    for ring_a, ring_b in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((ring_a[k], ring_a[(k + 1) % sides], ring_b[(k + 1) % sides],
                          ring_b[k]))
    bm.faces.new(rings[0])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, mat, "world", 1.0, smooth=True)


def head_shape(unit, scale=1.0):
    """Déforme un point de la sphère unité en tête d'anime : crâne rond, mâchoire étroite,
    menton pointu vers l'avant et le bas."""
    x, y, z = unit
    lower = max(0.0, -z)
    front = max(0.0, -y)
    x *= 1 - 0.42 * lower ** 1.4
    z -= 0.16 * lower * front
    y -= 0.06 * lower * front
    if y > 0:
        y *= 1.08
    return HEAD_CENTER + Vector((x * HEAD_SIZE.x, y * HEAD_SIZE.y, z * HEAD_SIZE.z)) * scale


def head_mesh(scale=1.0, keep=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=18, radius=1.0)
    if keep is not None:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
    for vertex in bm.verts:
        vertex.co = head_shape(vertex.co.copy(), scale)
    return bm


def scalp(azimuth, elevation, lift=1.06):
    """Point du cuir chevelu : azimut en degrés (0 = devant, 90 = gauche du perso), élévation
    en degrés au-dessus de l'équateur de la tête."""
    a, e = math.radians(azimuth), math.radians(elevation)
    return head_shape(Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e),
                              math.sin(e))), lift)


def outward(point, amount):
    direction = point - HEAD_CENTER
    return direction.normalized() * amount


def face_decal(x, z, size, mat, head_tree, tilt=0.0):
    """Petite plaque posée sur le visage, orientée selon la normale (yeux, sourcils, bouche)."""
    hit, normal, _, _ = head_tree.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5,
                          matrix=Matrix.Rotation(math.pi / 2, 4, "X"))
    bmesh.ops.scale(bm, vec=Vector((size[0], 1.0, size[1])), verts=bm.verts)
    bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(tilt, 3, "Y"), verts=bm.verts)
    rotation = Vector((0, -1, 0)).rotation_difference(normal).to_matrix()
    bmesh.ops.rotate(bm, cent=Vector(), matrix=rotation, verts=bm.verts)
    bmesh.ops.translate(bm, vec=hit + normal * 0.0012, verts=bm.verts)
    return finish(bm, mat, "face")


def head(spec):
    from mathutils.bvhtree import BVHTree
    name = spec["name"]
    female = spec["body"] == "female"
    bm = head_mesh()
    tree = BVHTree.FromBMesh(bm)
    parts = [finish(bm, "skin", "world", 1.0, smooth=True)]
    for side, mirrored in ((-1, True), (1, False)):
        eye_mat = name + "_eye" + ("_r" if mirrored else "_l")
        if eye_mat not in MATERIALS:
            image = image_from_array(eye_mat, textures.anime_eye(spec["eyes"], mirrored))
            material(eye_mat, metallic=0.0, roughness=0.6, texture=image)
        size = 0.052 if female else 0.046
        parts.append(face_decal(side * 0.043, 1.615, (size, size * 0.85), eye_mat, tree))
        parts.append(face_decal(side * 0.045, 1.655, (0.036, 0.007), paint(name + "_hair",
                                spec["hair_color"]), tree, tilt=side * (0.12 if female else 0.25)))
    parts.append(face_decal(0, 1.55, (0.02, 0.005), paint("mouth", (0.35, 0.1, 0.12)), tree))
    return parts


def body(spec):
    """Corps et vêtements en volumes Skin. Rend la liste des pièces et la position des mains."""
    name = spec["name"]
    big = spec["body"] == "big"
    female = spec["body"] == "female"
    coat = paint(name + "_coat", spec["coat"])
    pants = paint(name + "_pants", spec["pants"])
    shoulder = 0.21 if big else 0.155 if female else 0.175
    chest = (0.2, 0.13) if big else (0.135, 0.105) if female else (0.16, 0.1)
    waist = (0.15, 0.1) if big else (0.1, 0.075) if female else (0.115, 0.08)
    hip_x = 0.1 if big else 0.092 if female else 0.088
    pelvis = (0.155, 0.1) if big else (0.145, 0.095) if female else (0.13, 0.09)
    hand_x = shoulder + 0.095
    bulk = 1.25 if big else 0.95 if female else 1.0

    parts = []
    for side in (-1, 1):
        x = side * hip_x
        parts.append(skin_part([
            ((0, 0, 0.98), pelvis[0] * 0.8, pelvis[1]), ((x, 0, 0.88), 0.1 * bulk, 0.1 * bulk),
            ((x * 1.05, -0.01, 0.5), 0.07 * bulk, 0.072 * bulk),
            ((x * 1.1, 0.01, 0.16), 0.055 * bulk, 0.058 * bulk)],
            [(0, 1), (1, 2), (2, 3)], pants))
        parts.append(skin_part([
            ((x * 1.08, 0.0, 0.36), 0.078 * bulk, 0.08 * bulk),
            ((x * 1.1, 0.01, 0.1), 0.07 * bulk, 0.074 * bulk),
            ((x * 1.1, -0.12, 0.045), 0.058 * bulk, 0.05 * bulk)], [(0, 1), (1, 2)], "rubber"))

    puff = 0.02 if spec["outfit"] == "bomber" else 0.0
    torso = coat if spec["outfit"] != "armor" else "metal_dark"
    joints = [((0, 0, 0.98), pelvis[0] + puff, pelvis[1] + puff),
              ((0, 0, 1.1), waist[0] + puff, waist[1] + puff),
              ((0, 0.0, 1.3), chest[0] + puff, chest[1] + puff),
              ((0, 0, 1.45), 0.07, 0.065)]
    edges = [(0, 1), (1, 2), (2, 3)]
    for side in (-1, 1):
        base = len(joints)
        arm = [0.078 * bulk + puff, 0.062 * bulk + puff, 0.054 * bulk + puff]
        joints += [((side * shoulder, 0, 1.41), arm[0], arm[0]),
                   ((side * (shoulder + 0.055), 0.02, 1.15), arm[1], arm[1]),
                   ((side * (shoulder + 0.085), -0.01, 0.92), arm[2], arm[2])]
        edges += [(3, base), (base, base + 1), (base + 1, base + 2)]
    parts.append(skin_part(joints, edges, torso))
    parts.append(skin_part([((0, 0, 1.42), 0.042, 0.042), ((0, 0.005, 1.56), 0.04, 0.04)],
                           [(0, 1)], "skin"))
    for side in (-1, 1):
        parts.append(skin_part([
            ((side * (shoulder + 0.087), -0.012, 0.9), 0.05 * bulk, 0.042 * bulk),
            ((side * hand_x, -0.02, 0.82), 0.058 * bulk, 0.036 * bulk)], [(0, 1)], "rubber"))
    return parts, hand_x, chest, waist, shoulder, pelvis


def outfit(spec, chest, waist, shoulder, pelvis):
    name = spec["name"]
    coat = paint(name + "_coat", spec["coat"])
    accent = spec["accent"]
    style = spec["outfit"]
    parts = [
        limb((0, 0, 1.02), (0, 0, 1.06), waist[0] + 0.02, waist[0] + 0.02, "rubber", segments=20,
             flatten=waist[1] / waist[0] + 0.05),
        box((0.05, 0.01, 0.035), (0, -waist[1] - 0.025, 1.04), accent),
    ]
    if style == "trench":
        parts += [
            # Pans du manteau, ouverts en bas, plus longs derrière.
            limb((0, 0.005, 1.03), (0, 0.04, 0.4), pelvis[0] + 0.03, 0.29, coat, segments=20,
                 flatten=0.88, caps=False),
            limb((0, 0.04, 0.415), (0, 0.04, 0.4), 0.293, 0.293, accent, segments=20,
                 flatten=0.89, caps=False),
            # Col montant largement ouvert.
            limb((0, 0.02, 1.4), (0, 0.04, 1.54), 0.085, 0.12, coat, segments=16, flatten=0.9,
                 caps=False),
        ]
    elif style == "bomber":
        parts += [
            limb((0, 0, 0.93), (0, 0, 0.98), waist[0] + 0.04, waist[0] + 0.04, "rubber",
                 segments=20, flatten=0.8),
            sphere((0.26, 0.21, 0.09), (0, 0.02, 1.45), coat, segments=18),
            box((0.012, 0.008, 0.4), (0, -(chest[1] + 0.02) - 0.005, 1.17), accent),
        ]
    else:
        parts += [
            box((0.4, 0.14, 0.32), (0, -0.07, 1.25), coat, bevel=0.05),
            box((0.18, 0.01, 0.025), (0, -0.145, 1.3), accent),
            limb((0, 0, 1.0), (0, 0.02, 0.62), waist[0] + 0.05, 0.25, coat, segments=12,
                 flatten=0.8, caps=False),
        ]
    # Épaulettes arrondies : la signature des héros d'anime de l'époque.
    pad = 0.2 if style == "armor" else 0.13
    for side in (-1, 1):
        parts.append(sphere((pad, pad + 0.04, 0.09), (side * (shoulder + 0.02), 0, 1.47),
                            coat, segments=16,
                            rotation=(0, side * -0.35, 0)))
        parts.append(box((0.025, pad, 0.015), (side * (shoulder + 0.07), 0, 1.46), accent,
                         rotation=(0, side * -0.35, 0)))
    return parts


def bangs(hair, count, spread, length, sweep=0.0, width=0.034):
    parts = []
    for i in range(count):
        azimuth = -spread + 2 * spread * i / max(count - 1, 1)
        root = scalp(azimuth, 52)
        tip = root + Vector((azimuth / 900 + sweep, -0.035, -length))
        control = root + Vector((0, -0.05, -length * 0.3))
        parts.append(strand(root, control, tip, width, hair))
    return parts


def hairstyle(spec):
    hair = paint(spec["name"] + "_hair", spec["hair_color"])
    style = spec["hair"]
    if style == "buzz":
        cap = head_mesh(1.04, keep=lambda co: co.z > 0.25 or (co.y > -0.2 and co.z > -0.2))
        parts = [finish(cap, hair, "world", 1.0, smooth=True)]
        for azimuth in range(-40, 50, 20):
            root = scalp(azimuth, 62, 1.02)
            parts.append(strand(root, root + Vector((0, -0.02, 0.02)),
                                root + Vector((0, -0.04, 0.025)), 0.03, hair))
        return parts

    cap = head_mesh(1.07, keep=lambda co: co.z > 0.4 or (co.y > -0.15 and co.z > -0.55)
                    or (abs(co.x) > 0.8 and co.z > -0.3))
    parts = [finish(cap, hair, "world", 1.0, smooth=True)]
    up = Vector((0, 0, 1))
    if style == "spiky":
        # Pics rejetés vers l'arrière, plus longs derrière, aucun vers le visage.
        for azimuth in range(60, 310, 25):
            for elevation in (30, 60):
                root = scalp(azimuth + elevation / 3, elevation)
                back = 0.5 + 0.5 * -math.cos(math.radians(azimuth))
                tip = root + outward(root, 0.06 + 0.06 * back) + up * 0.02 + Vector((0, 0.07, 0))
                parts.append(strand(root, root + outward(root, 0.05), tip, 0.05, hair))
        for azimuth in (-30, 0, 30):
            root = scalp(azimuth, 75)
            parts.append(strand(root, root + up * 0.06, root + up * 0.1 + Vector((0, 0.1, 0)),
                                0.05, hair))
        parts += bangs(hair, 5, 40, 0.11)
        for side in (-1, 1):
            root = scalp(side * 75, 25)
            parts.append(strand(root, root + Vector((side * 0.01, -0.02, -0.06)),
                                root + Vector((side * 0.0, -0.03, -0.14)), 0.03, hair))
    elif style == "swept":
        for azimuth in range(-60, 70, 20):
            root = scalp(azimuth, 50)
            parts.append(strand(root, root + Vector((azimuth / 600, 0.04, 0.09)),
                                root + Vector((azimuth / 350, 0.24, -0.06)), 0.045, hair))
        for azimuth in range(100, 270, 25):
            root = scalp(azimuth, 20)
            parts.append(strand(root, root + outward(root, 0.04),
                                root + outward(root, 0.03) + Vector((0, 0.04, -0.16)), 0.04,
                                hair))
        root = scalp(-15, 55)
        parts.append(strand(root, root + Vector((-0.02, -0.05, -0.05)),
                            root + Vector((-0.05, -0.03, -0.19)), 0.03, hair))
    elif style == "bob":
        for azimuth in range(40, 330, 18):
            root = scalp(azimuth, 30)
            parts.append(strand(root, root + outward(root, 0.04),
                                root + outward(root, 0.035) + Vector((0, 0, -0.17)), 0.05,
                                hair))
        parts += bangs(hair, 7, 45, 0.085, width=0.03)
    elif style == "ponytail":
        parts += bangs(hair, 5, 40, 0.12, sweep=0.02)
        tie = scalp(180, 35, 1.1)
        parts.append(sphere((0.05, 0.05, 0.05), tie, "neon_gold"))
        for k in range(6):
            angle = k * math.pi / 3
            offset = Vector((math.cos(angle) * 0.02, math.sin(angle) * 0.015, 0))
            parts.append(strand(tie + offset, tie + offset + Vector((0, 0.12, -0.08)),
                                tie + offset * 2 + Vector((0, 0.1, -0.55)), 0.04, hair))
        for side in (-1, 1):
            root = scalp(side * 70, 30)
            parts.append(strand(root, root + Vector((0, -0.02, -0.08)),
                                root + Vector((0, -0.02, -0.18)), 0.025, hair))
    elif style == "twintails":
        parts += bangs(hair, 6, 45, 0.1)
        for side in (-1, 1):
            tie = scalp(side * 105, 40, 1.1)
            parts.append(sphere((0.05, 0.05, 0.05), tie, "neon_pink"))
            for k in range(5):
                angle = k * 2 * math.pi / 5
                offset = Vector((math.cos(angle) * 0.02, math.sin(angle) * 0.02, 0))
                parts.append(strand(tie + offset, tie + offset + Vector((side * 0.12, 0, 0.02)),
                                    tie + offset * 2 + Vector((side * 0.16, 0.04, -0.5)), 0.04,
                                    hair))
    return parts


def hunter(spec):
    """Assemble un hunter d'environ 1,75 m (1,85 m pour le costaud)."""
    parts, hand_x, chest, waist, shoulder, pelvis = body(spec)
    parts += head(spec)
    parts += outfit(spec, chest, waist, shoulder, pelvis)
    parts += hairstyle(spec)
    parts += weapon(spec["weapon"], spec["accent"], hand_x)
    obj = join(spec["name"], parts)
    if spec["body"] == "big":
        obj.scale = (1.06, 1.06, 1.06)
    elif spec["body"] == "female":
        obj.scale = (0.96, 0.96, 0.96)
    return obj


def weapon(kind, accent, hand_x):
    hand = Vector((hand_x, -0.02, 0.86))
    if kind == "sword":
        # Épée vibrante portée dans le dos, en diagonale.
        return [
            box((0.05, 0.015, 0.95), (0.02, 0.2, 1.1), "trim_light", rotation=(0, 0.55, 0)),
            box((0.014, 0.022, 0.9), (0.035, 0.2, 1.1), accent, rotation=(0, 0.55, 0)),
            limb((-0.28, 0.2, 1.52), (-0.2, 0.2, 1.4), 0.025, 0.025, "rubber"),
            box((0.16, 0.04, 0.03), (-0.19, 0.2, 1.4), "metal_dark", rotation=(0, 0.55, 0)),
        ]
    if kind == "hammer":
        head = Vector((hand_x + 0.06, -0.24, 0.14))
        return [
            limb(hand + Vector((0, 0, 0.08)), head, 0.025, 0.025, "metal_dark"),
            box((0.24, 0.34, 0.24), head, "metal_dark", bevel=0.03, rotation=(0.3, 0, 0)),
            box((0.25, 0.02, 0.06), head + Vector((0, -0.17, 0.05)), accent, rotation=(0.3, 0, 0)),
        ]
    if kind == "rifle":
        center = hand + Vector((0.02, -0.04, -0.22))
        return [
            box((0.06, 0.12, 0.62), center, "metal_dark", bevel=0.01),
            box((0.07, 0.08, 0.16), center + Vector((0, 0.02, 0.36)), "rubber"),
            limb(center - Vector((0, 0.02, 0.3)), center - Vector((0, 0.02, 0.55)), 0.018, 0.018,
                 "metal_dark"),
            box((0.065, 0.02, 0.4), center + Vector((0, -0.065, 0)), accent),
        ]
    if kind == "pistols":
        parts = []
        for side in (-1, 1):
            parts += [
                box((0.07, 0.16, 0.13), (side * 0.2, -0.02, 0.84), "metal_dark", bevel=0.01),
                box((0.075, 0.02, 0.1), (side * 0.2, -0.105, 0.84), accent),
            ]
        return parts
    if kind == "scythe":
        top = Vector((0.3, 0.22, 1.95))
        return [
            limb((-0.3, 0.22, 0.45), top, 0.022, 0.022, "metal_dark"),
            box((0.6, 0.02, 0.1), top + Vector((-0.25, 0, 0.0)), "trim_light",
                rotation=(0, -0.35, 0)),
            box((0.6, 0.025, 0.02), top + Vector((-0.25, 0, -0.05)), accent,
                rotation=(0, -0.35, 0)),
        ]
    parts = []
    for side in (-1, 1):
        grip = Vector((side * hand_x, -0.03, 0.86))
        parts += [
            box((0.04, 0.012, 0.42), grip + Vector((0, -0.02, -0.25)), "trim_light"),
            box((0.012, 0.02, 0.4), grip + Vector((side * -0.02, -0.02, -0.25)), accent),
        ]
    return parts


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
    ] + [hunter(spec) for spec in HUNTERS]
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
    alpha_input = bsdf.inputs["Alpha"]
    if alpha_input.links:
        cutout = nodes.new("ShaderNodeMixShader")
        links.new(alpha_input.links[0].from_socket, cutout.inputs["Fac"])
        links.new(nodes.new("ShaderNodeBsdfTransparent").outputs[0], cutout.inputs[1])
        links.new(total.outputs[0], cutout.inputs[2])
        total = cutout
    links.new(total.outputs[0], output.inputs["Surface"])


def add_bloom(path, threshold=0.88, strength=1.2):
    """Halo autour des néons, ajouté après le rendu (le compositeur exige un GPU)."""
    import numpy as np
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    # Seules les couleurs vives et saturées (néons) bavent ; le blanc d'un vêtement non.
    saturation = pixels[..., :3].max(axis=2) - pixels[..., :3].min(axis=2)
    bright = np.clip(pixels[..., :3] - threshold, 0, None) * np.clip(saturation * 2, 0, 1)[..., None]
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
    place(kit, "hunter_kaz", (6.0, 1.2, 0), math.radians(-150))
    place(kit, "hunter_sable", (2.4, 4.6, 0), math.radians(30))

    point_light((1.0, 6.0, 2.4), NEON_PINK, 150)
    point_light((-0.5, 3.0, 2.2), NEON_TEAL, 100)
    point_light((5.0, 3.0, 2.0), NEON_TEAL, 60)
    point_light((8.0, 6.0, 2.4), (1.0, 0.55, 0.2), 120)
    point_light((8.0, 0.0, 1.0), NEON_GREEN, 40)
    shoot(path, Vector((4.0, 3.0, 0.8)), 15.5, (1280, 1000))


def render_lineup(kit, path):
    """Les six hunters côte à côte, sur un sol de la salle, vus en iso de plus près."""
    KIT.hide_render = True
    for x in range(-1, 2):
        for y in range(-1, 2):
            place(kit, "floor_room", (x * TILE * 2, y * TILE, 0)).scale = (2, 1, 1)
    azimuth = math.radians(20)
    row = Vector((math.cos(azimuth), math.sin(azimuth), 0))
    for i, spec in enumerate(HUNTERS):
        place(kit, spec["name"], row * (i - 2.5) * 1.25, azimuth - math.radians(15))
    point_light((-3.0, -2.0, 2.5), NEON_PINK, 120)
    point_light((3.0, -2.0, 2.5), NEON_TEAL, 120)
    shoot(path, Vector((0.0, 0.0, 0.95)), 7.2, (1600, 900), azimuth=20)


def render_portrait(kit, path):
    """Gros plan sur les visages de Kaz et Nova, pour juger les têtes et les coiffures."""
    KIT.hide_render = True
    place(kit, "floor_room", (0, 0, 0))
    place(kit, "hunter_kaz", (-0.22, 0, 0), math.radians(-10))
    place(kit, "hunter_nova", (0.25, 0.05, 0), math.radians(12))
    point_light((-1.0, -1.0, 2.0), NEON_PINK, 12)
    point_light((1.0, -1.0, 2.0), NEON_TEAL, 12)
    shoot(path, Vector((0.0, 0.0, 1.5)), 1.1, (1200, 800), azimuth=0, elevation=78)


def shoot(path, target, ortho_scale, resolution, azimuth=45, elevation=57):
    """Rend la scène en cel-shading : lune lavande, contours sombres, halo sur les néons."""
    sun_data = bpy.data.lights.new("moon", "SUN")
    sun_data.color = (0.85, 0.82, 1.0)
    sun_data.energy = 3.0
    sun_data.angle = 0.05
    sun = bpy.data.objects.new("moon", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))

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
    camera_data.ortho_scale = ortho_scale
    camera = bpy.data.objects.new("Camera", camera_data)
    scene.collection.objects.link(camera)
    camera.rotation_euler = (math.radians(elevation), 0, math.radians(azimuth))
    forward = camera.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    camera.location = target - forward * 40
    scene.camera = camera

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = resolution
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
        glowing = [slot.material is not None and (slot.material.name.startswith(
            ("neon", "screen", "relic", "floor", "grating", "mouth")) or "_eye" in slot.material.name
           ) for slot in obj.material_slots]
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
    elif "--portrait" in sys.argv:
        render_portrait(kit_objects, os.path.join(KIT_DIR, "portrait.png"))
    elif "--lineup" in sys.argv:
        render_lineup(kit_objects, os.path.join(KIT_DIR, "hunters.png"))
