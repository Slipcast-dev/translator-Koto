**Русский** | [English](CONTRIBUTING.en.md)

# Участие

См. [статус](Docs/STATUS.md) и [сборку](Docs/BUILDING.md). В bug report укажите версию Koto/macOS, архитектуру, движок, минимальные шаги и ожидаемое поведение. Используйте вымышленные фразы; не публикуйте ключи и личные снимки/текст.

Обращения и предложения принимаются на русском и английском языках.

Одна задача — один ограниченный diff с соответствующими проверками. Сохраняйте Swift 6 strict concurrency, отмену/защиту от устаревших ответов, privacy gates и отсутствие весов в Git. Комментарии объясняют причины решений. Проверки не должны удалять системные языки или автоматически скачивать большую модель.

Перед значимым кодовым вкладом согласуйте с владельцем условия его распространения. Не включайте чужой код без соответствующих условий; сохраняйте сторонние notices.

## License and community

Koto is under a [proprietary license](LICENSE): modifying and distributing it requires the author's written consent. A contribution you submit is licensed to the author as described in section 5 of the license (use, modify, distribute and relicense it as part of Koto); submit only what you have the right to. Preserve Copyright (c) 2026 Slipcast-Dev and third-party notices. Follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Before submitting, run `bash script/test_swift_ci.sh` and `swiftlint lint --strict --config .swiftlint.yml`. Dependabot submodule updates must also update the reviewed commit and SHA-256 source locks; do not merge an unverified runtime revision.
