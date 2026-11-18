# Concept : la destruction, matière par matière

Validé le 18 novembre 2026. Ce document passe avant le code : si un retour
le contredit, on le corrige d'abord, puis le code.

## Le jeu, pour l'instant

Une brute géante, seule, casse une ville jouet, vue à la 3e personne. Pas
de combat pour l'instant : on règle d'abord la destruction.

À garder absolument : la ville générée, différente à chaque partie, et
l'échelle géante.

## Le principe

La matière seule dit comment une pièce répond à un choc.

- Un bâtiment est un assemblage de pièces simples : poteau, poutre, dalle,
  panneau. Il est creux, ce n'est plus un bloc plein découpé en cailloux.
- Chaque pièce est faite d'une matière.
- Seul un choc casse : un coup de la brute, ou un morceau lourd qui tombe
  dessus. Marcher ne casse rien.
- Ce qui n'est plus porté tombe.
- La résistance se règle par matière et par pièce, jamais par éclat.
  Changer la découpe ne dérègle rien.

## L'effet géant

Les morceaux tombent lentement, comme de vrais immeubles vus de loin. C'est
ce qui donne sa taille à la brute.

La vitesse de chute est un seul réglage, le même pour toutes les matières.
Sa valeur se choisit au banc d'essai, sur le téléphone.

Choix fait : la brute garde ses mouvements actuels. Seuls les morceaux
tombent lentement.

## Les quatre matières

Quatre matières, quatre réponses : le verre éclate, le bois casse net, le
béton se fissure puis lâche, le métal plie.

| Matière | Réponse à un choc | Elle cède | Morceaux | Ce qui reste au sol |
| --- | --- | --- | --- | --- |
| Verre | Éclate, le panneau entier | Au premier choc | Paillettes qui tombent droit | Rien : elles disparaissent |
| Bois | Casse net, là où il est frappé | En un coup | Longs morceaux légers qui volent loin | Du petit bois que la brute pousse du pied |
| Béton | Se fissure à vue, puis lâche | Après plusieurs coups | Quelques gros blocs lourds : la pièce bascule à l'opposé du coup et se disloque en tombant (voir la note) | Des blocs lourds, couchés, en tas bas |
| Métal | Plie et garde la forme | Jamais en morceaux ; trop plié, il se couche | Aucun : il reste d'un seul tenant | Une pièce tordue, couchée |

Qui porte : le béton et le métal portent des étages, le bois porte une
maison, le verre ne porte rien.

Note sur le béton (étape 2, à valider) : la page disait d'abord que ses
blocs « tombent droit ». Au banc, des blocs laissés là où ils étaient
restaient empilés : un poteau cassé tenait encore debout et portait encore
sa dalle. C'est le même défaut que le morceau coincé dans son trou de la
version précédente. La pièce bascule donc à l'opposé du coup, et ses blocs
se séparent en tombant : l'ouverture est dégagée et les gravats sont
couchés, bas.

## Maison, immeuble, tour

Chaque bâtiment casse à sa façon parce qu'il n'est pas fait des mêmes
matières.

| Bâtiment | Fait de | Comment il casse |
| --- | --- | --- |
| Maison | Bois | D'un coup, en petit bois qui vole |
| Immeuble | Béton et verre | Les vitres éclatent, puis chaque dalle tombe à plat quand ses poteaux ont lâché |
| Tour | Métal et verre | Le verre pleut, l'ossature plie, penche et se couche d'un seul tenant |

Ces mélanges ne se construisent qu'une fois les quatre matières validées.

## Comment on avance

Une matière à la fois, sur un banc d'essai en grey box, validée sur le
téléphone avant la suivante.

- Le banc d'essai : un sol vide, la brute, et quelques pièces de la matière
  (un mur, un poteau, une dalle posée sur des poteaux).
- Grey box : formes simples, couleurs unies, aucun décor, aucune texture.
  Le seul modèle est le mannequin de la brute.
- La ville générée revient quand les quatre matières sont validées.

Le plan, une pull request par étape, chacune jouable sur le téléphone
(béton d'abord : validé ; l'ordre des trois autres matières est proposé) :

1. Banc vide : la brute seule sur un sol nu. (fait)
2. Béton. (fait, à valider sur le téléphone)
3. Métal : c'est la partie neuve, autant savoir tôt si le téléphone suit.
4. Bois.
5. Verre.
6. Maison, immeuble, tour sur le banc.
7. La ville générée revient, faite de ces bâtiments.

## Ce qui prouvera que c'est bon

Cinq vérifications, en grey box, sur le téléphone :

1. Sans couleur, on reconnaît la matière rien qu'à sa façon de casser.
2. Le verre cède au premier choc, le béton pas avant plusieurs coups, le
   métal jamais en morceaux.
3. Marcher ne casse rien.
4. Les gravats ne cachent jamais la brute.
5. La chute des morceaux fait sentir la taille de la brute.

## Gardé pour plus tard

Le combat revient après la destruction. Choix déjà notés :

- Les dégâts qui mènent au K.O. viennent moitié des poings, moitié de la
  ville.
- Une partie se joue en 2 manches gagnantes, dans la même ville qui ne se
  répare pas.
- À terme, plusieurs styles de brute.
- Ramasser et lancer des morceaux de ville : plus tard.

Pas décidé : d'autres matières que ces quatre.

## Ce que la version précédente a appris

Elle est gardée telle quelle sur la branche `archive/v1`.

- Un bâtiment plein découpé en cailloux casse comme un rocher, pas comme un
  immeuble, et n'a pas d'intérieur.
- Un morceau arraché à un bâtiment plein reste coincé dans son trou, et une
  brute ne peut pas entrer dans un trou plus bas qu'elle.
- Régler la résistance « à N coups par morceau » se dérègle dès qu'on change
  la découpe.
- À la 3e personne, les gravats et les trous cachent la caméra.
- Tout casser en marchant casse le fun ; tout casser pareil ne ressemble pas
  à une destruction d'immeuble.
- Le décor (façades, voitures, sol, poussière) est arrivé avant que la base
  soit bonne.
