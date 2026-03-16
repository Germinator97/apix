.PHONY: help test analyze format coverage clean all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: analyze test ## Run analyze and test

test: ## Run all tests
	flutter test

analyze: ## Run dart analyze and format check
	dart analyze --fatal-infos
	dart format --set-exit-if-changed .

format: ## Format code
	dart format .

coverage: ## Run tests with coverage report
	flutter test --coverage
	@echo "Coverage report generated in coverage/lcov.info"

clean: ## Clean build artifacts
	flutter clean
	rm -rf coverage/
