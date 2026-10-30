# Lalabob — commandes de développement
# Prérequis : Xcode 27, XcodeGen (brew install xcodegen)

PROJECT := Lalabob.xcodeproj
KIT     := Packages/LalabobKit

.PHONY: help setup team project open build test format clean

help: ## Affiche cette aide
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-8s %s\n", $$1, $$2}'

setup: ## Vérifie les outils et crée Config/Local.xcconfig
	@command -v xcodegen >/dev/null || { echo "XcodeGen manquant : brew install xcodegen"; exit 1; }
	@test -f Config/Local.xcconfig || { cp Config/Local.xcconfig.example Config/Local.xcconfig; \
		echo "Config/Local.xcconfig créé (signature locale par défaut, rien à remplir)."; }

team: ## Affiche l'identifiant d'équipe de votre certificat Apple Development
	@id=$$(security find-certificate -c "Apple Development" -p 2>/dev/null \
		| openssl x509 -noout -subject 2>/dev/null \
		| sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p'); \
	if [ -n "$$id" ]; then echo "DEVELOPMENT_TEAM = $$id"; \
	else echo "Aucun certificat : ouvrez Xcode › Réglages › Comptes, ajoutez votre identifiant Apple, puis compilez une fois."; fi

project: setup ## Génère Lalabob.xcodeproj depuis project.yml
	xcodegen generate

open: project ## Génère puis ouvre le projet dans Xcode
	open $(PROJECT)

build: project ## Compile l'app (Debug)
	xcodebuild -project $(PROJECT) -scheme Lalabob -configuration Debug -destination 'platform=macOS' build

test: ## Lance les tests des modules cœur
	cd $(KIT) && swift test

format: ## Formate le code Swift
	swift format --in-place --recursive App $(KIT)/Sources $(KIT)/Tests

clean: ## Supprime les fichiers générés
	rm -rf $(PROJECT) $(KIT)/.build DerivedData
