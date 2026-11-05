#!/usr/bin/env python3
"""Generates levels/sandbox.tscn: the imperial district of Le Demolisseur.

A forum in the middle (a temple on its podium, two-storey arcades along
its sides, a round domed temple closing the north avenue, a triumphal arch
on the way in), a ring of imperial blocks around it, walkways between the
blocks at the 2nd and 3rd floors and switchback ramps to reach them.

Run:  python3 tools/make_district.py
"""
import math
import os
OUT=os.path.join(os.path.dirname(__file__),'..','levels','sandbox.tscn')
MAT={'concrete':0,'wood':1,'metal':2}
KIND={'wall':0,'tower':1,'stack':2,'pillars':3,'building':4,'ramp':5,'bridge':6,'apartment':7,'arcade':8,'keep':9,'dome':10,'temple':11}
def xf(x,y,z,rot=0.0):
    a=math.radians(rot); c=round(math.cos(a),4); s=round(math.sin(a),4)
    rows=[c,0,s, 0,1,0, -s,0,c]
    return "Transform3D(%s, %s, %s, %s)"%(", ".join(str(v) for v in rows),x,y,z)
def st(name,kind,pos,counts,block,strength=3.0,mat='concrete',accent=None,rot=0.0,seed=0,doors=None,overhang=0.0):
    L=['[node name="%s" type="Node3D" parent="."]'%name,'transform = '+xf(*pos,rot),'script = ExtResource("2_structure")']
    if KIND[kind]: L.append('kind = %d'%KIND[kind])
    L.append('counts = Vector3i(%d, %d, %d)'%counts)
    L.append('block = Vector3(%s, %s, %s)'%block)
    L.append('strength = %s'%strength)
    if MAT[mat]: L.append('material = %d'%MAT[mat])
    acc=MAT[accent] if accent else MAT[mat]
    if acc: L.append('accent_material = %d'%acc)
    if seed: L.append('seed_value = %d'%seed)
    if doors: L.append('doors = PackedVector3Array(%s)'%", ".join("%d, %d, %d"%d for d in doors))
    if overhang: L.append('end_overhang = %s'%overhang)
    L.append('style = 1')  # imperial
    return "\n".join(L)
BAY=4.0; STO=3.2; NB=3; HALF=NB*BAY/2  # 12 m buildings
COL_OFF=0.55  # walkway columns stand this far off the facades
S=[]
seed=[0]
def nxt():
    seed[0]+=1; return seed[0]
# name -> (cx, cz, storeys, mat, accent). The four inner blocks of the
# old crossroads are gone: that is the forum now.
B={
 'NO_ext':(-29,-14,4,'concrete','concrete'), 'NO_int2':(-12,-31,6,'concrete','metal'), 'NO_ext2':(-29,-31,5,'concrete','wood'),
 'NE_ext':(29,-14,5,'concrete','wood'), 'NE_int2':(12,-31,5,'concrete','concrete'), 'NE_ext2':(29,-31,6,'concrete','metal'),
 'SO_ext':(-29,14,4,'concrete','wood'), 'SO_int2':(-12,31,4,'concrete','wood'), 'SO_ext2':(-29,31,5,'metal','concrete'),
 'SE_ext':(29,14,5,'concrete','concrete'), 'SE_int2':(12,31,4,'concrete','metal'), 'SE_ext2':(29,31,4,'concrete','wood'),
}
D={k:[] for k in B}
# Ramp in the alley east of a block, flights toward +z from the street.
def ramp_se(west,east,flights):
    cx,cz=B[west][0],B[west][1]
    ox=cx+HALF+0.3; oz=cz-HALF
    S.append(st('Rampe'+west,'ramp',(ox,0,oz),(1,flights,1),(2.2,STO,NB*BAY-4.0),3.5,'concrete','wood',seed=nxt()))
    for j in range(1,flights+1):
        b = NB-1 if j%2==1 else 0
        D[west].append((3,b,j)); D[east].append((2,b,j))
# The same, turned round, in the alley west of a block.
def ramp_no(west,east,flights):
    cx,cz=B[east][0],B[east][1]
    ox=cx-HALF-0.3; oz=cz+HALF
    S.append(st('Rampe'+east,'ramp',(ox,0,oz),(1,flights,1),(2.2,STO,NB*BAY-4.0),3.5,'concrete','metal',rot=180,seed=nxt()))
    for j in range(1,flights+1):
        b = 0 if j%2==1 else NB-1
        D[west].append((3,b,j)); D[east].append((2,b,j))
ramp_se('SE_int2','SE_ext2',3)
ramp_no('NO_ext2','NO_int2',3)
def bridge_x(name,west,east,storey,bay=1):
    top=storey*STO; drums=round((top-0.3)/1.4); h=round((top-0.3)/drums,4)
    z=B[west][1]-HALF+(bay+0.5)*BAY
    x0=B[west][0]+HALF+COL_OFF; x1=B[east][0]-HALF-COL_OFF
    spans=4; S.append(st(name,'bridge',((x0+x1)/2,0,z),(spans,drums,1),(round((x1-x0)/spans,4),h,2.6),2.5,'concrete','wood',seed=nxt(),overhang=COL_OFF-0.12))
    D[west].append((3,bay,storey)); D[east].append((2,bay,storey))
def bridge_z(name,north,south,storey,bay=1):
    top=storey*STO; drums=round((top-0.3)/1.4); h=round((top-0.3)/drums,4)
    x=B[north][0]-HALF+(bay+0.5)*BAY
    z0=B[north][1]+HALF+COL_OFF; z1=B[south][1]-HALF-COL_OFF
    spans=2; S.append(st(name,'bridge',(x,0,(z0+z1)/2),(spans,drums,1),(round((z1-z0)/spans,4),h,2.6),2.5,'concrete','concrete',rot=90,seed=nxt(),overhang=COL_OFF-0.12))
    D[north].append((1,bay,storey)); D[south].append((0,bay,storey))
# Walkways: over both avenues, and over the alleys to the corner blocks.
bridge_x('PontNord','NO_int2','NE_int2',3)
bridge_x('PontSud','SO_int2','SE_int2',2)
bridge_z('PontOuest','NO_ext2','NO_ext',2)
bridge_z('PontEst','NE_ext2','NE_ext',3)
bridge_z('PontSudOuest','SO_ext','SO_ext2',3)
bridge_z('PontSudEst','SE_ext','SE_ext2',2)
for k,(cx,cz,n,mat,acc) in B.items():
    S.append(st('Immeuble_'+k,'apartment',(cx,0,cz),(NB,n,NB),(BAY,STO,0.45),3.0,mat,acc,seed=nxt(),doors=D[k]))
# The forum: the temple on its podium, facing the way in (+z).
S.append(st('Temple','temple',(0,0,-3),(6,9,1),(3.2,8.0,1.0),4.0,seed=nxt()))
# Two-storey arcades along its sides (a storey = 6.4 m, like the blocks).
S.append(st('PortiqueOuest','arcade',(-19.5,0,-3),(5,2,1),(3.0,4.03,1.4),4.0,rot=90,seed=nxt()))
S.append(st('PortiqueEst','arcade',(19.5,0,-3),(5,2,1),(3.0,4.03,1.4),4.0,rot=90,seed=nxt()))
# A round domed temple closing the north avenue, a triumphal arch on the
# way in from the south.
S.append(st('Tholos','dome',(0,0,-40),(12,14,9),(5.5,0.7,0.8),4.0,seed=nxt()))
S.append(st('ArcDeTriomphe','arcade',(0,0,22),(1,1,1),(6.0,6.0,3.0),5.0,seed=nxt()))
# A bronze belvedere on a roof: it comes down with its block (anchors).
S.append(st('Belvedere','tower',(12,5*STO,-31),(2,5,1),(1.2,0.8,0.35),2.5,'metal',seed=nxt()))
# Blocks closing the far ends of the avenues.
S.append(st('FondSud','apartment',(0,0,46),(3,4,2),(BAY,STO,0.45),3.0,'concrete','wood',seed=nxt()))
S.append(st('FondOuest','apartment',(-44,0,0),(2,5,4),(BAY,STO,0.45),3.0,'concrete','concrete',seed=nxt()))
S.append(st('FondEst','apartment',(44,0,0),(2,4,4),(BAY,STO,0.45),3.0,'metal','concrete',seed=nxt()))
hint=("Le forum impérial. Tout se casse. Le trou noir fait tourner tout ce qui entre dans son rayon et broie ce qui est autour. "
      "Le bouclier : une coque de glace noire qui t'entoure par l'avant, dès que tu touches son bouton. Monte par les rampes "
      "des ruelles, traverse les ponts entre les immeubles. Un débris lancé suffit à te mettre K.O.")
out=['[gd_scene load_steps=4 format=3]','',
'[ext_resource type="Script" path="res://scripts/game/level.gd" id="1_level"]',
'[ext_resource type="Script" path="res://scripts/destruction/structure.gd" id="2_structure"]',
'[ext_resource type="Script" path="res://scripts/game/skyline.gd" id="3_skyline"]','',
'[node name="Sandbox" type="Node3D"]','script = ExtResource("1_level")','title = "Bac à sable"','hint = "%s"'%hint,'',
'[node name="PlayerStart" type="Marker3D" parent="."]','transform = '+xf(0,0.05,40),'',
'[node name="Skyline" type="Node3D" parent="."]','script = ExtResource("3_skyline")','']
for s_ in S: out+=[s_,'']
open(OUT,'w').write("\n".join(out))
print("ok", len(S))
