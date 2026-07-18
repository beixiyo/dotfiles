#!/usr/bin/env bun

import { existsSync, statSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { assertCmd, fzf, FUNC_DIR, BUN_SRC, detectClipCopy, shellQuote } from './fzf-shared'

async function main(): Promise<void> {
  assertCmd('fzf')

  let dir = '.'
  let noIgnore = ''
  const positional: string[] = []
  const argv = process.argv.slice(2)

  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '-I': case '--no-ignore': noIgnore = '--no-ignore'; break
      case '--': positional.push(...argv.slice(i + 1)); i = argv.length; break
      default: if (!argv[i].startsWith('-')) positional.push(argv[i])
    }
  }
  if (positional.length > 0 && existsSync(positional[0]) && statSync(positional[0]).isDirectory()) {
    dir = positional[0]
  }

  const noIgnoreStr = noIgnore ? ` ${noIgnore}` : ''
  const rgNoIgnore = noIgnore ? ' --no-ignore-vcs' : ''

  const rgBase = `rg --column --line-number --no-heading --color=never --smart-case --hidden --no-ignore-parent${rgNoIgnore} --glob '!.git'`
  const fsChangeReload = `${rgBase} {q} ${shellQuote(dir)} < /dev/null | bun run '${BUN_SRC}/fs-list.ts' 2>/dev/null || true`

  const clipCmd = detectClipCopy()
  const panel = `${FUNC_DIR}/_actions/fx-panel.sh`

  // 动态 channel 状态：放进 mkdtemp 私有随机目录（0700），channel 文件以
  // wx（O_CREAT|O_EXCL）+ 0600 预创建——目录私有且随机、文件拒绝跟随预置 symlink，
  // 杜绝 /tmp（1777）下可预测路径被劫持写穿
  const stateDir = mkdtempSync(join(tmpdir(), 'fzf-fx-'))
  try {
    const chStateFile = join(stateDir, 'channel')
    writeFileSync(chStateFile, '0\n', { flag: 'wx', mode: 0o600 })

    // 静态状态：改为进程环境继承直接传递给 fzf 及其回调子进程（fx-panel.sh 直接读 env），
    // 彻底移除被 source 的环境文件。注意 Bun.spawn 默认 env 是启动快照、不含运行时新增变量，
    // 必须显式传 env
    const fzfEnv = {
      ...process.env,
      _FX_FUNC_DIR: FUNC_DIR,
      _FX_BUN_SRC: BUN_SRC,
      _FX_DIR: dir,
      _FX_NO_IGNORE: noIgnore,
      _FX_RG_NO_IGNORE: rgNoIgnore.trim(),
      _FX_CLIP_CMD: clipCmd,
      _FX_CH_STATE: chStateFile,
    }

    const ffReload = `bun run '${BUN_SRC}/ff-list.ts' --dir ${shellQuote(dir)} --type a${noIgnoreStr} 2>/dev/null < /dev/null`

    const listResult = Bun.spawnSync(
      ['bun', 'run', `${BUN_SRC}/ff-list.ts`, '--dir', dir, '--type', 'a', ...(noIgnore ? [noIgnore] : [])],
      { stdout: 'pipe', stderr: 'pipe' },
    )
    const list = listResult.stdout.toString()

    const proc = Bun.spawn(['fzf',
      '--ansi',
      '--delimiter', '\x01',
      '--with-nth', '1,2',
      '--prompt', ' Files> ',
      '--preview', `${FUNC_DIR}/_preview/ff.sh {2}`,
      '--preview-window', 'right:60%:border-left',
      '--bind', fzf.scrollBinds,

      '--bind', `change:reload(${fsChangeReload})`,
      '--bind', `start:unbind(change)+reload(${ffReload})+transform-header(${panel} init)+transform-footer(${panel} footer)`,

      '--bind', `tab:transform(${panel} switch-next {q})`,
      '--bind', `shift-tab:transform(${panel} switch-prev {q})`,
      '--bind', `enter:transform(${panel} enter {2})`,
      '--bind', `click-footer:transform(${panel} click "$FZF_CLICK_FOOTER_WORD" {2})`,

      '--bind', `${fzf.cmd}-o:execute(code {2})`,
      '--bind', `${fzf.opt}-o:execute(nvim {2} < /dev/tty)`,
      '--bind', `${fzf.opt}-c:execute-silent(bun run '${BUN_SRC}/path.ts' abs {+2} 2>/dev/null | ${clipCmd})`,
    ], {
      stdin: Buffer.from(list),
      stdout: 'inherit',
      stderr: 'inherit',
      env: fzfEnv,
    })
    await proc.exited
  }
  finally {
    // 只清理自己 mkdtemp 出来的私有目录
    try { rmSync(stateDir, { recursive: true, force: true }) } catch {}
  }
}

main().catch(() => process.exit(1))
