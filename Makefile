.DEFAULT_GOAL := help
SHELL := /bin/bash

SCHEME  := FaceRitual
PROJECT := FaceRitual.xcodeproj
DESTINATION ?= platform=iOS Simulator,name=iPhone 15 Pro

.PHONY: help
help: ## 显示可用命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# 任何机器都能跑（含 Windows / Linux / CI）
# ---------------------------------------------------------------------------

.PHONY: content
content: ## 校验内容包 JSON（不需要 Xcode）
	python tools/validate_content.py

.PHONY: teeth
teeth: ## 反向验证：确认每条内容校验规则真的会报错
	python tools/check_validator_teeth.py

.PHONY: golden
golden: ## 重新生成几何 golden vectors（改了 anchors.json 后必须跑）
	python tools/golden/generate_golden.py

.PHONY: arch
arch: ## 架构约束 + 轻量 Swift 静态检查（不需要 Xcode）
	python tools/check_architecture.py

.PHONY: refs
refs: ## Swift 跨文件引用检查（枚举 case / init 标签 / 协议一致性）
	python tools/check_swift_refs.py

.PHONY: simulate
simulate: ## 无头跑一遍全部 routine，验证每一段都能在脸上画出东西
	python tools/simulate_routine.py

.PHONY: prototype
prototype: ## 生成并打开浏览器版 AR 概念验证（不需要 Mac / iPhone）
	python tools/build_prototype.py
	@echo ""
	@echo "接下来在这个目录起个本地服务，然后用 Chrome 打开 http://127.0.0.1:8000 ："
	@echo "    cd prototype && python -m http.server 8000"
	@echo ""
	@echo "必须走 http 而不是双击文件：file:// 下浏览器会拦掉 CDN 模块与摄像头权限。"

.PHONY: check
check: arch refs content teeth golden simulate ## 跑所有不依赖 Xcode 的校验

# ---------------------------------------------------------------------------
# 需要 macOS + Xcode
# ---------------------------------------------------------------------------

.PHONY: bootstrap
bootstrap: ## 生成 Xcode 工程（需 macOS）
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "缺少 xcodegen。执行: brew install xcodegen"; exit 1; }
	xcodegen generate
	@echo "已生成 $(PROJECT)。用 'make open' 打开。"

.PHONY: open
open: ## 在 Xcode 中打开工程
	open $(PROJECT)

.PHONY: core-test
core-test: ## 只跑 FaceRitualCore 的单元测试（最快的反馈回路）
	cd Packages/FaceRitualCore && swift test

.PHONY: build
build: ## 构建 App（模拟器）
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' | xcbeautify || \
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)'

.PHONY: test
test: ## 跑全部测试（模拟器）
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)'

.PHONY: clean
clean: ## 清理构建产物与生成的工程
	rm -rf $(PROJECT) build .build
	cd Packages/FaceRitualCore && rm -rf .build
