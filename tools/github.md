## action

- https://upptime.js.org/docs/get-started
- https://shazow.net/posts/github-issues-as-a-hugo-frontend/

- https://github.blog/2021-04-15-work-with-github-actions-in-your-terminal-with-github-cli/
  - 使用 github action 来构造函数
- https://github.com/Mayandev/interview-schedule/issues/19 : 使用 Google Calendar 来自动更新 github

- [ ] https://posthog.com/blog/automating-a-software-company-with-github-actions
  - 作者介绍他们公司如何使用 GitHub Actions，将各种开发步骤自动化，举了很多例子，演示了测试、代码格式化、构建、部署的配置文件应该怎么写。

### 一些有用的 action
- [issue 翻译](https://github.com/usthe/issues-translate-action)
- https://github.com/osmoscraft/osmosfeed : 将 github 仓库变为 rss 订阅

## 使用 lint-md 来检查中文文档
```yml
name: Lint Markdown By Lint Markdown

on:
  push:
    branches: [ master ]
  pull_request:
    branches: [ master ]

jobs:
  lint-markdown:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2

      - name: lint-md-github-action
        uses: lint-md/github-action@v0.0.2
        with:
                files: './doc'
                configFile: '.lintmdrc'
                failOnWarnings: true
```
2. 创建 `.lintmdrc`
    - `.lintmdrc` 中的内容为 `{}`

## token
1. 创建 https://github.com/settings/tokens
2. 将 ~/.git-credentials 中原来的密码替换为 token:
```txt
https://martins3:token@github.com
```
