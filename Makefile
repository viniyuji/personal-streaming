COMPOSE ?= docker compose

.PHONY: init up down restart ps logs config vpn plex gpu host

init:
	./scripts/init-dirs.sh

up: init
	$(COMPOSE) up -d

down:
	$(COMPOSE) down --remove-orphans

restart:
	$(COMPOSE) restart

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail 100

config:
	$(COMPOSE) config

vpn: init
	$(COMPOSE) -f docker-compose.yml -f docker-compose.vpn.yml up -d

plex: init
	$(COMPOSE) -f docker-compose.yml -f docker-compose.plex.yml up -d

gpu:
	@echo "A UHD 620 já entra no compose principal (/dev/dri). Use: make up"

host:
	./scripts/install-host.sh
