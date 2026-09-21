# TP Optimisation Docker

## Conditions communes

### Environnement de mesure

- Processeur : Intel Core i5-12600KF.
- Docker Desktop avec des conteneurs Linux.
- Construction avec `--no-cache` pour désactiver le cache des instructions de build. Les couches de l'image de base peuvent toutefois être déjà présentes localement.

### Commandes

```powershell
#par exemple:
$version = "v0-baseline"
docker build --no-cache -t "node-app:$version" -f .\dockerfile .
docker run -d --name "node-app-$version" -p 3000:3000 "node-app:$version"
docker image ls --tree  "node-app:$version"
```

## Comparaison globale

### Taille des images

| Étape | Image | Disk Usage | Content Size | Réduction du contenu | Optimisation |
| :--- | :--- | ---: | ---: | :--- | :--- |
| **0 — Baseline** | `node-app:v0-baseline` | **1.93 GB** | **485 MB** | — | Image initiale |
| **1 — Dockerignore** | `node-app:v1-dockerignore` | **1.93 GB** | **484 MB** | **≈ 1 MB (0.21 %) vs étape 0** | Réduction du contexte de build |
| **2 — Cache** | `node-app:v2-cache` | **1.93 GB** | **484 MB** | **0 MB (0 %) vs étape 1** | Réorganisation des couches |
| **3 — Alpine** | `node-app:v3-alpine` | **283 MB** | **69.8 MB** | **≈ 414.2 MB (85.6 %) vs étape 2** | Base Alpine et retrait des paquets système |
| **4 — Dépendances de production** | `node-app:v4-production-deps` | **278 MB** | **68.9 MB** | **≈ 0.9 MB (1.3 %) vs étape 3** | Installation des dépendances de production |

Le passage à Alpine produit la réduction principale : le contenu de l'image passe de **484 MB à 69.8 MB**. L'installation limitée aux dépendances de production réduit ensuite le contenu à **68.9 MB**.

### Temps de construction

Les mesures suivantes utilisent `--no-cache` afin de reconstruire toutes les instructions du Dockerfile.

- **Temps total** : durée affichée par Docker à la fin du build.
- **Récupération de la base** : durée de l'étape `FROM`, comprenant le téléchargement et l'extraction de l'image de base.
- **Temps hors récupération** : temps total moins la durée de l'étape `FROM`.


| Étape | État de l'image de base | Temps total | Récupération de la base | Temps hors récupération |
| :--- | :--- | ---: | ---: | ---: |
| **0 — Baseline** | Téléchargée pendant le build | **46.2 s** | **30.1 s** | **≈ 16.1 s** |
| **0 — Baseline** | Déjà disponible localement | **13.9 s** | **0.0 s** | **13.9 s** |
| **1 — Dockerignore** | Déjà disponible localement | **15.9 s** | **0.0 s** | **15.9 s** |
| **2 — Cache** | Déjà disponible localement | **16.7 s** | **0.0 s** | **16.7 s** |
| **3 — Alpine** | Téléchargée pendant le build | **20.4 s** | **15.6 s** | **≈ 4.8 s** |
| **3 — Alpine** | Déjà disponible localement | **≈ 4.5 s** | **0.0 s** | **≈ 4.5 s** |
| **4 — Dépendances de production** | Déjà disponible localement | **4.7 s** | **0.0 s** | **4.7 s** |
| **4 — Dépendances de production** | Téléchargée après nettoyage | **14.7 s** | **10.5 s** | **≈ 4.2 s** |

Après retrait du temps de récupération de la base, les étapes 0 à 2 demandent environ **14 à 17 secondes**. Le passage à Alpine ramène ce temps à environ **4.5 secondes**. La différence entre les deux bases provient principalement du retrait de l'installation des paquets Debian et de l'utilisation d'une image plus légère.

Les reconstructions avec cache de l'étape 2 sont détaillées dans la section correspondante.

## Étape 0 — Baseline

### Résultats

- Taille sur disque : **1.93 GB**.
- Taille du contenu : **485 MB**.
- Construction initiale : **46.2 s**.
- Récupération et extraction de l'image `node:latest` : **30.1 s**.
- Temps estimé hors récupération de la base : **16.1 s**.
- Construction avec la base déjà disponible localement : **13.9 s**.

La mesure locale utilise le code du commit `117acfc` et la même référence d'image de base, fixée par digest.

### Preuves d'exécution

![Construction de l'image baseline et taille finale](docs-images/0/1.png)

![Taille disque et taille du contenu de l'image baseline](docs-images/0/2.png)

![Construction de la baseline sans cache des instructions avec la base déjà disponible localement](docs-images/add-comparison/0-local.png)

## Étape 1 — Réduction du contexte de build

### Pourquoi ajouter un `.dockerignore` ?

Le contexte de build regroupe les fichiers accessibles à Docker pendant la construction. Avec `COPY . /app`, les fichiers non exclus du contexte sont copiés dans l'image, y compris les dépendances locales, les données Git et la documentation.

Le fichier `.dockerignore` exclut les éléments inutiles à la construction et à l'exécution de l'application. Cela réduit les fichiers à transmettre et à copier, et évite que des modifications de documentation ou de journaux invalident le cache de cette instruction lors des builds avec cache. Les fichiers restent présents sur la machine.

### Modifications

- **Ajout du `.dockerignore` :**

```dockerignore
node_modules/
.git/
docs-images/
README.md
*.log
```

`node_modules/` est exclu car les dépendances sont installées dans l'image, ce qui évite aussi les incompatibilités possibles entre Windows et Linux. `.git/` contient l'historique de version, inutile au serveur. `docs-images/` et `README.md` servent uniquement au compte rendu du TP. `*.log` exclut les journaux locaux à la racine, inutiles au build.

- **Adaptation du `Dockerfile` :**

Suppression de la copie locale des dépendances :

```dockerfile
COPY node_modules ./node_modules
```

Ce dossier n'étant plus accessible dans le contexte de build, cette instruction échouerait. Les dépendances sont directement générées dans l'image par `RUN npm install`.

### Impact

La taille du contexte transmis à Docker passe d'environ **205.10 kB à 163 B**. La taille du contenu de l'image passe de **485 MB à 484 MB**, soit une réduction d'environ **1 MB (0.21 %)**.

La construction avec `--no-cache` prend **15.9 s** avec l'image de base déjà disponible localement. L'apport principal du `.dockerignore` concerne la réduction du contexte et la stabilité du cache lorsque des fichiers de documentation ou des fichiers locaux changent.

### Preuves d'exécution

![Construction de l'image après ajout du dockerignore](docs-images/1/1.png)

![Taille disque et taille du contenu après ajout du dockerignore](docs-images/1/2.png)

## Étape 2 — Réutilisation du cache des dépendances

### Pourquoi réorganiser les instructions ?

À l'étape 1, `COPY . /app` précède les installations npm et système. Une nouvelle version de `server.js` peut donc entraîner leur réexécution, même lorsque les dépendances restent identiques.

Séparer la copie des fichiers de dépendances de celle du code permet de conserver le cache des installations lorsque seul le code du serveur change.

### Modifications

- **Copie des fichiers de dépendances avant l'installation :**

```dockerfile
COPY package.json package-lock.json ./
RUN npm install
```

`package.json` déclare les dépendances et les scripts du projet ; `package-lock.json` enregistre les versions résolues.

- **Déplacement de la copie du code après les installations npm et système :**

```dockerfile
COPY . /app
```

Lorsque les fichiers de dépendances restent identiques et que le cache est disponible, Docker réutilise les couches d'installation. La nouvelle copie du code et le build sont exécutés si aucun cache correspondant à ce contenu n'existe déjà. Les commandes d'installation et les paquets restent inchangés.

### Impact

La réorganisation des instructions cible le temps de reconstruction pendant le développement.

À l'étape 1, `COPY . /app` est exécuté avant `npm install` et `apt-get`. Une modification de `server.js` invalide donc toutes les couches suivantes.

À l'étape 2, les fichiers de dépendances sont copiés avant les installations :

```dockerfile
COPY package.json package-lock.json ./
RUN npm install
RUN apt-get update && apt-get install -y build-essential ca-certificates locales && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

COPY . /app
```

Une modification de `server.js` conserve ainsi les couches contenant `npm install` et l'installation des paquets système.

| Scénario | Couches réutilisées | Temps total | Réduction par rapport au build sans cache |
| :--- | :--- | ---: | ---: |
| Build avec `--no-cache` | Aucune couche d'instruction | **16.7 s** | Référence |
| Reconstruction sans modification | Toutes les couches disponibles | **1.6 s** | **15.1 s (90.4 %)** |
| Reconstruction après modification de `server.js` | Installation npm et paquets système | **2.2 s** | **14.5 s (86.8 %)** |

Le build avec `--no-cache` passe de **15.9 s à l'étape 1** à **16.7 s à l'étape 2**, soit **0.8 s de plus**. Dans cette configuration, Docker réexécute `npm install`, `apt-get` et l'export de l'image. L'ordre des instructions apporte son gain lors des reconstructions avec cache.

L'instruction `COPY package.json package-lock.json ./` supplémentaire est mesurée à **0.0 s**. L'écart observé sur le build complet provient principalement des durées d'installation et d'export.

Avec le cache complet, la construction descend à **1.6 s**. Après modification de `server.js`, Docker réexécute uniquement la copie du code, `npm run build` et l'export de l'image, pour un total de **2.2 s**.

### Preuves d'exécution

![Construction sans cache puis reconstruction avec cache](docs-images/2/1.png)

![Taille disque et taille du contenu après réorganisation des couches](docs-images/2/2.png)

![Reconstruction après modification du serveur avec réutilisation du cache des installations](docs-images/2/3.png)

## Étape 3 — Passage à une base Alpine

### Pourquoi utiliser Alpine ?

L'image `node:latest` repose sur une base Debian contenant de nombreux outils système. La variante `node:alpine` fournit Node.js et npm sur une base plus légère. L'objectif est de réduire la taille de l'image tout en conservant le fonctionnement du serveur.

### Modifications

- **Remplacement de l'image de base :**

```dockerfile
FROM node:alpine
```

- **Suppression de l'installation des paquets Debian et de la génération de locale :**

```dockerfile
RUN apt-get update && apt-get install -y build-essential ca-certificates locales && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen
```

Alpine utilise `apk` à la place d'`apt-get`, mais aucune installation système supplémentaire n'est nécessaire pour les fonctionnalités testées. Les dépendances actuelles ne montrent pas de besoin de compilation native sous Linux et le script `build` se limite à un affichage.

### Impact sur la taille

| Mesure | Étape 2 | Étape 3 | Réduction |
| :--- | ---: | ---: | ---: |
| Disk Usage | 1.93 GB | **283 MB** | **≈ 85.3 %** |
| Content Size | 484 MB | **69.8 MB** | **≈ 85.6 %** |

L'utilisation de l'espace disque (Disk Usage) et la taille du contenu (Content Size) diminuent considérablement. Cela résulte principalement du passage à une base Alpine et de la suppression des paquets système supplémentaires.

### Impact sur le temps de construction

La construction initiale prend **20.4 s**, dont **15.6 s** pour récupérer et extraire l'image `node:alpine`. Le temps hors récupération de la base est donc estimé à **4.8 s**.

Avec `node:alpine` déjà disponible localement, une construction avec `--no-cache` prend environ **4.5 s**.

Le temps hors récupération de la base passe ainsi d'environ **16.7 s à l'étape 2** à **4.5–4.8 s à l'étape 3**. Ce gain provient du passage à Alpine et du retrait de l'installation des paquets Debian.

### Vérification manuelle

Les vérifications manuelles ont confirmé le fonctionnement du serveur sous Alpine sans problèmes.

### Preuves d'exécution

![Construction de l'image Alpine et mesure de sa taille](docs-images/3/1.png)

## Étape 4 — Installation des dépendances de production

### Pourquoi exclure les dépendances de développement ?

Le conteneur démarre avec `node server.js`. Il n'utilise pas `nodemon`, destiné au redémarrage automatique pendant le développement. Installer cet outil et ses dépendances spécifiques dans l'image augmente sa taille sans contribuer au fonctionnement du serveur.

### Modifications

Remplacement de `RUN npm install` par :

```dockerfile
RUN npm ci --omit=dev
```

`npm ci` installe les versions du fichier `package-lock.json` sans le modifier et échoue si les déclarations de dépendances ne correspondent pas à `package.json`. L'option `--omit=dev` exclut du disque les dépendances réservées au développement. `nodemon` reste déclaré pour le développement local ; `express` et `mongodb`, déclarés dans `dependencies`, restent installés dans l'image.

Le script `build` actuel se limite à un affichage et ne nécessite aucun outil de développement. Cette sélection des dépendances ne change pas le mode d'exécution du serveur : la configuration `NODE_ENV=development` reste celle des étapes précédentes.

### Impact sur la taille

| Mesure | Étape 3 | Étape 4 | Réduction |
| :--- | ---: | ---: | ---: |
| Disk Usage | 283 MB | **278 MB** | **≈ 5 MB (1.8 %)** |
| Content Size | 69.8 MB | **68.9 MB** | **≈ 0.9 MB (1.3 %)** |


### Impact sur le temps de construction

| Condition | Temps total | Récupération de la base | Temps hors récupération |
| :--- | ---: | ---: | ---: |
| Base `node:alpine` déjà disponible localement | **4.7 s** | **0.0 s** | **4.7 s** |
| Après nettoyage, avec `--pull --no-cache` | **14.7 s** | **10.5 s** | **≈ 4.2 s** |

Le temps hors récupération reste proche de celui de l'étape 3 : environ **4.5 s** à l'étape 3 et **4.2–4.7 s** à l'étape 4.

L'installation avec `npm ci --omit=dev` apporte principalement une réduction de taille, de **69.8 MB à 68.9 MB**.

### Preuves d'exécution

![Construction avec les dépendances de production et mesure de la taille de l'image](docs-images/4/1.png)

![Construction après nettoyage du cache avec téléchargement de l'image de base](docs-images/4/2.png)
