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

## Comparaison des optimisations

| Étape | Image | Disk Usage | Content Size | Réduction du contenu | Build avec `--no-cache` | Optimisation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **0 — Baseline** | `node-app:v0-baseline` | **1.93 GB** | **485 MB** | — | **46.2 s** | Image initiale non optimisée |
| **1 — Dockerignore** | `node-app:v1-dockerignore` | **1.93 GB** | **484 MB** | **≈ 1 MB (0.21 %)** | **15.9 s** | Réduction du contexte de build |
| **2 — Cache** | `node-app:v2-cache` | **1.93 GB** | **484 MB** | **0 MB (0 %) vs étape 1** | **16.7 s** | Réorganisation des couches pour réutiliser le cache des installations |

## Étape 0 — Baseline

### Résultats

- Image construite à partir du code source et du Dockerfile d'origine non modifiés.
- Taille sur disque : **1.93 GB**.
- Taille du contenu : **485 MB**.
- Temps de construction à froid : **46.2 secondes**.

### Preuves d'exécution

![Construction de l'image baseline et taille finale](docs-images/0/1.png)

![Taille disque et taille du contenu de l'image baseline](docs-images/0/2.png)

## Étape 1 — Réduction du contexte de build

### Pourquoi ajouter un `.dockerignore` ?

Le contexte de build regroupe les fichiers accessibles à Docker pendant la construction. Avec `COPY . /app`, les fichiers non exclus du contexte sont copiés dans l'image, y compris les dépendances locales, les données Git et la documentation.

Le fichier `.dockerignore` exclut les éléments inutiles à la construction et à l'exécution de l'application. Cela réduit les fichiers à transmettre et à copier, et évite que des modifications de documentation ou de journaux invalident le cache de cette instruction lors des builds avec cache. Les fichiers restent présents sur la machine ; les règles n'affectent pas leur suivi par Git.

### Modifications

- **Ajout du `.dockerignore` :**

```dockerignore
node_modules/
.git/
docs-images/
README.md
*.log
```

`node_modules/` est exclu car les dépendances sont installées dans l'image, ce qui évite aussi les incompatibilités possibles entre Windows et Linux. `.git/` contient l'historique de version, inutile au serveur. `docs-images/` et `README.md` servent uniquement au compte rendu du TP. `*.log` exclut les journaux locaux à la racine, inutiles au build. Ces règles ne suppriment aucun fichier local et n'affectent pas leur suivi par Git.

- **Adaptation du `Dockerfile` :**

Suppression de la copie locale des dépendances :

```dockerfile
COPY node_modules ./node_modules
```

Ce dossier n'étant plus accessible dans le contexte de build, cette instruction échouerait. Les dépendances sont directement générées dans l'image par `RUN npm install`.

### Impact

La taille du contenu passe de **485 MB à 484 MB**, soit une réduction d'environ **1 MB (0,21 %)**.

Le principal effet du `.dockerignore` est de réduire le contexte de build et d'éviter la copie de fichiers inutiles dans l'image.

Le temps de build mesuré passe de **46.2 s à 15.9 s**, mais cette différence ne peut pas être attribuée uniquement au `.dockerignore`, certaines couches de l'image de base pouvant déjà être présentes localement.

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

Cette optimisation vise à réduire le temps de reconstruction ; elle n'entraîne donc pas de réduction visible de la taille par rapport à l'étape 1.

| Mesure de l'étape 2 | Résultat |
| :--- | ---: |
| Build avec `--no-cache` | **16.7 s** |
| Build avec réutilisation du cache existant | **1.6 s** |
| Reconstruction après modification de `server.js` (`node-app:v2-cache-test`) | **2.2 s** |

Lors du test suivant, après modification de `server.js`, `COPY package.json package-lock.json ./`, `RUN npm install` et l'installation des paquets système affichent toujours `CACHED`, tandis que `COPY . /app` et `RUN npm run build` sont réexécutés, pour un temps total affiché de **2.2 secondes**.

### Preuves d'exécution

![Construction sans cache puis reconstruction avec cache](docs-images/2/1.png)

![Taille disque et taille du contenu après réorganisation des couches](docs-images/2/2.png)

![Reconstruction après modification du serveur avec réutilisation du cache des installations](docs-images/2/3.png)
