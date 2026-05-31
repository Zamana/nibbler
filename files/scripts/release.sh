#!/bin/bash

# =============================================================================
# release.sh — Sincroniza com upstream, compila e publica release no GitHub
#
# Pré-requisitos:
#   - GITHUB_TOKEN exportado no ambiente (ex: ~/.zshrc)
#   - Node.js e npm instalados
#   - git configurado
#
# Uso: sh files/scripts/release.sh
# =============================================================================

set -e

REPO="Zamana/nibbler"
UPSTREAM="https://github.com/rooklift/nibbler.git"
SRC_DIR="files/src"
DIST_DIR="$SRC_DIR/dist"

# --- Verificações iniciais ---

if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ GITHUB_TOKEN não definido. Adicione ao ~/.zshrc:"
  echo "   export GITHUB_TOKEN=seu_token_aqui"
  exit 1
fi

cd "$(dirname "$0")/../.." || exit 1
echo "📁 Diretório: $(pwd)"

# --- Sincronizar com upstream ---

echo ""
echo "🔄 Sincronizando com upstream..."

if ! git remote | grep -q upstream; then
  git remote add upstream "$UPSTREAM"
  echo "   Remote 'upstream' adicionado."
fi

git fetch upstream

# Verificar se há atualizações
UPSTREAM_COMMITS=$(git rev-list HEAD..upstream/master --count)
if [ "$UPSTREAM_COMMITS" -eq 0 ]; then
  echo "✅ Já está atualizado com o upstream. Nada a fazer."
  exit 0
fi

echo "   $UPSTREAM_COMMITS commit(s) novo(s) encontrado(s)."
git merge upstream/master --no-edit

# --- Obter versão ---

VERSION=$(node -e "console.log(require('./$SRC_DIR/package.json').version)")
TAG="v$VERSION"
echo ""
echo "📦 Versão: $VERSION"

# Verificar se o release já existe
EXISTING=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG")

if [ "$EXISTING" = "200" ]; then
  echo "⚠️  Release $TAG já existe no GitHub. Abortando."
  exit 0
fi

# --- Compilar ---

echo ""
echo "🔨 Compilando..."
cd "$SRC_DIR"
sh build_mac.sh
cd ../..

# --- Commitar mudanças ---

echo ""
echo "💾 Commitando..."
git add -A
git diff --cached --quiet || git commit -m "Release $VERSION"
git push origin master

# --- Criar release no GitHub ---

echo ""
echo "🚀 Criando release $TAG no GitHub..."

RELEASE_BODY="Nibbler $VERSION compilado para macOS ARM (Apple Silicon) e Intel."

RELEASE_RESPONSE=$(curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/$REPO/releases" \
  -d "{
    \"tag_name\": \"$TAG\",
    \"name\": \"Nibbler $VERSION\",
    \"body\": \"$RELEASE_BODY\",
    \"draft\": false,
    \"prerelease\": false
  }")

RELEASE_ID=$(echo "$RELEASE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

if [ -z "$RELEASE_ID" ]; then
  echo "❌ Falha ao criar release. Resposta:"
  echo "$RELEASE_RESPONSE"
  exit 1
fi

echo "   Release criado (ID: $RELEASE_ID)"

# --- Upload dos artefatos ---

echo ""
echo "📤 Fazendo upload dos artefatos..."

upload_asset() {
  local FILE="$1"
  local NAME=$(basename "$FILE")
  echo "   Enviando $NAME..."
  curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$FILE" \
    "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$NAME" \
    > /dev/null
}

upload_asset "$DIST_DIR/Nibbler-${VERSION}-arm64.dmg"
upload_asset "$DIST_DIR/Nibbler-${VERSION}-arm64-mac.zip"
upload_asset "$DIST_DIR/Nibbler-${VERSION}.dmg"
upload_asset "$DIST_DIR/Nibbler-${VERSION}-mac.zip"

# --- Concluído ---

echo ""
echo "✅ Release $TAG publicado com sucesso!"
echo "   https://github.com/$REPO/releases/tag/$TAG"
