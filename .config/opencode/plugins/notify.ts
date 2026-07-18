import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "os"

const HOME = homedir()
const DB = `${HOME}/.local/share/opencode/opencode.db`

const SQL_LAST_Q = [
  "SELECT json_extract(p.data,'$.text') FROM part p",
  "JOIN message m ON p.message_id=m.id",
  "WHERE json_extract(m.data,'$.role')='user'",
  "AND json_extract(p.data,'$.type')='text'",
  "ORDER BY p.time_created DESC LIMIT 1;",
].join(" ")

export const NotifyPlugin: Plugin = async ({ $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "permission.asked") {
        try {
          await $`bash ${HOME}/.zsh/notify-stop.sh ${"opencode needs you"}`
        } catch { }
        return
      }

      if (event.type !== "session.idle") return
      try {
        const title = (await $`sqlite3 ${DB} ${"SELECT title FROM session ORDER BY time_updated DESC LIMIT 1;"}`.text()).trim()
        const lastQ = (await $`sqlite3 ${DB} ${SQL_LAST_Q}`.text()).trim().slice(0, 50)
        const context = [title, lastQ].filter(Boolean).join("\n")
        await $`bash ${HOME}/.zsh/notify-stop.sh opencode ${context}`
      } catch { }
    }
  }
}
