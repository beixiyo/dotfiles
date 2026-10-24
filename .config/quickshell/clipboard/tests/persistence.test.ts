/** 使用 Bun 测试框架，在隔离 XDG 目录中验证真实 QML 控制器的持久化行为 */
import { afterEach, describe, expect, test } from 'bun:test'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const source = process.env.QS_TEST_SOURCE || resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=', 'base64')
const fixtures = new Set<string>()

afterEach(() => {
  for (const fixture of fixtures) rmSync(fixture, { recursive: true, force: true })
  fixtures.clear()
})

describe('剪贴板置顶持久化', () => {
  test('清单损坏时保留原文件和图片快照', () => {
    const { pinFile, image } = runScenario('invalid-list')

    expect(readFileSync(pinFile, 'utf8')).toBe('{broken-json')
    expect(readFileSync(image)).toEqual(png)
  })

  test('快照解码失败时不新增置顶或残留图片', () => {
    const { pinFile, original, pins } = runScenario('failed-snapshot')

    expect(readFileSync(pinFile, 'utf8')).toBe(original)
    expect(existsSync(join(pins, '99.png'))).toBe(false)
  })

  test('图片解码成功后保存快照及正确 MIME', () => {
    const { pinFile, pins } = runScenario('valid-snapshot')

    expect(readFileSync(join(pins, '99.png'))).toEqual(png)
    expect(JSON.parse(readFileSync(pinFile, 'utf8'))[0].imageMime).toBe('image/png')
  })

  test('历史已不存在时仍可从置顶快照另存图片', () => {
    const { pictures, fixture } = runScenario('save-pinned-image')
    const outputs = readdirSync(join(pictures, 'Clipboard'))

    expect(outputs).toHaveLength(1)
    expect(readFileSync(join(pictures, 'Clipboard', outputs[0]))).toEqual(png)
    expect(existsSync(join(fixture, 'decode.log'))).toBe(false)
  })

  test('清单替换失败时保留旧清单及其图片', () => {
    const { pinFile, original, image } = runScenario('failed-save')

    expect(readFileSync(pinFile, 'utf8')).toBe(original)
    expect(readFileSync(image)).toEqual(png)
  })

  test('连续保存最终写入最新状态', () => {
    const { pinFile } = runScenario('queued-save')

    expect(JSON.parse(readFileSync(pinFile, 'utf8'))[0].id).toBe('52')
  })

  test('取消置顶保存失败后清空历史，仍保护磁盘清单引用的图片', () => {
    const { pinFile, original, image } = runScenario('failed-save-then-clear')

    expect(readFileSync(pinFile, 'utf8')).toBe(original)
    expect(readFileSync(image)).toEqual(png)
  })

  test('取消置顶成功保存后回收不再被引用的图片', () => {
    const { pinFile, image } = runScenario('unpin-success')

    expect(JSON.parse(readFileSync(pinFile, 'utf8'))).toEqual([])
    expect(existsSync(image)).toBe(false)
  })
})

/** 用命令替身注入故障，运行真实控制器并返回可供断言的磁盘路径 */
function runScenario(scenario: Scenario) {
  const fixture = mkdtempSync(join(tmpdir(), 'qs-pins-test-'))
  fixtures.add(fixture)

  const config = join(fixture, 'config', 'quickshell')
  const data = join(fixture, 'data')
  const pins = join(data, 'qs-clipboard', 'pins')
  const bin = join(fixture, 'bin')
  const runtime = join(fixture, 'runtime')
  const pictures = join(fixture, 'pictures')
  for (const dir of [pins, bin, runtime, pictures]) mkdirSync(dir, { recursive: true, mode: 0o700 })
  cpSync(source, config, { recursive: true })

  const image = join(pins, '42.png')
  const pinFile = join(pins, 'pins.json')
  const original = JSON.stringify([{ id: '42', isImage: true, imageExt: 'png', imageFile: image, imageMime: 'image/png' }])
  writeFileSync(image, png)
  writeFileSync(pinFile, scenario === 'invalid-list' ? '{broken-json' : original)
  writeFileSync(
    join(bin, 'cliphist'),
    '#!/bin/bash\nif [ "$1" = decode ]; then\n  echo decode >> "$QS_TEST_ROOT/decode.log"\n  [ "$QS_TEST_CASE" = valid-snapshot ] || exit 1\n  cat "$QS_TEST_ROOT/input.png"\nfi\n',
    { mode: 0o700 },
  )
  writeFileSync(join(bin, 'xdg-user-dir'), '#!/bin/bash\nprintf "%s\\n" "$QS_TEST_ROOT/pictures"\n', { mode: 0o700 })
  writeFileSync(join(fixture, 'input.png'), png)
  if (scenario === 'failed-save' || scenario === 'failed-save-then-clear') writeFileSync(join(bin, 'mv'), '#!/bin/bash\nexit 1\n', { mode: 0o700 })

  const actions: Record<Scenario, string> = {
    'invalid-list': 'ctl.gcOrphanPins(); ctl.savePins()',
    'failed-snapshot': 'ctl.pinItem({id: "99", isImage: true, imageExt: "png"})',
    'valid-snapshot': 'ctl.pinItem({id: "99", isImage: true, imageExt: "png"})',
    'save-pinned-image': 'ctl.previewItem = ctl.pinnedItems[0]; ctl.savePreviewImageToDisk()',
    'failed-save': 'ctl.pinnedItems = []; ctl.savePins()',
    'queued-save': 'ctl.pinnedItems = [{id: "51", copyText: "first"}]; ctl.savePins(); ctl.pinnedItems = [{id: "52", copyText: "latest"}]; ctl.savePins()',
    'failed-save-then-clear': 'ctl.unpinItem(ctl.pinnedItems[0])',
    'unpin-success': 'ctl.unpinItem(ctl.pinnedItems[0])',
  }
  const checks: Partial<Record<Scenario, string>> = {
    'failed-snapshot': 'if (ctl.pinnedItems.length !== 1) Qt.exit(1)',
    'valid-snapshot': 'if (ctl.pinnedItems.length !== 2) Qt.exit(1)',
    'save-pinned-image': 'if (ctl.saveImageRunning || ctl.saveImageStatus === "保存失败") Qt.exit(1)',
  }
  writeFileSync(
    join(config, 'shell.qml'),
    `
import QtQuick
import Quickshell
import qs.clipboard
ShellRoot {
  ClipboardController { id: ctl }
  Timer { interval: 400; running: true; onTriggered: { ${actions[scenario]} } }
  Timer { interval: 800; running: ${scenario === 'failed-save-then-clear'}; onTriggered: ctl.clearAll() }
  Timer { interval: 1300; running: true; onTriggered: { ${checks[scenario] || ''}; Qt.quit() } }
}
`,
  )
  const result = Bun.spawnSync(['qs', '-p', join(config, 'shell.qml'), '--no-color'], {
    env: {
      ...process.env,
      HOME: fixture,
      XDG_CONFIG_HOME: join(fixture, 'config'),
      XDG_DATA_HOME: data,
      XDG_RUNTIME_DIR: runtime,
      QT_QPA_PLATFORM: 'offscreen',
      WAYLAND_DISPLAY: '',
      PATH: `${bin}:${process.env.PATH}`,
      QS_TEST_ROOT: fixture,
      QS_TEST_CASE: scenario,
    },
    timeout: 8000,
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const logs = result.stdout.toString() + result.stderr.toString()
  expect(result.exitCode, logs).toBe(0)
  expect(logs).not.toMatch(/Failed to load configuration|ReferenceError|TypeError/)

  expect(readdirSync(pins).filter((name) => name.startsWith('.pins.') || name.startsWith('.snapshot.'))).toEqual([])

  return { fixture, pinFile, pins, original, image, pictures }
}

type Scenario =
  | 'invalid-list'
  | 'failed-snapshot'
  | 'valid-snapshot'
  | 'save-pinned-image'
  | 'failed-save'
  | 'queued-save'
  | 'failed-save-then-clear'
  | 'unpin-success'
