.PHONY: all up stop down logs wp-shell db-shell pma nginx-logs wp-logs db-logs bot-logs bot-shell status rebuild

# Start all services in the background
up:
	docker compose up -d --build

# Stop and remove containers, networks are kept, volumes are kept
stop:
	docker compose down

# Stop and remove everything including volumes (DANGER: data loss)
down:
	docker compose down -v

# View logs for all services
logs:
	docker compose logs -f

# View logs for a specific service
nginx-logs:
	docker compose logs -f nginx

wp-logs:
	docker compose logs -f wordpress

db-logs:
	docker compose logs -f db

bot-logs:
	docker compose logs -f bot

bot-shell:
	docker compose exec bot sh

# Open a shell inside the WordPress container
wp-shell:
	docker compose exec wordpress sh

# Open a shell inside the database container
db-shell:
	docker compose exec db sh

# Open MariaDB CLI (prompts for password — use the one from .env)
db-cli:
	docker compose exec db mariadb -u wp_user -p omni_shop

# Open phpMyAdmin in browser (Linux/Mac/WSL)
pma:
	@echo "Opening phpMyAdmin at http://localhost:8081"
	@python3 -m webbrowser http://localhost:8081 2>/dev/null || xdg-open http://localhost:8081 2>/dev/null || open http://localhost:8081 2>/dev/null || echo "Open your browser and go to: http://localhost:8081"

# View status of all containers
status:
	docker compose ps

# Clean build (useful after Dockerfile changes)
rebuild:
	docker compose down
	docker compose build --no-cache
	docker compose up -d
