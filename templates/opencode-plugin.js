export const CcNotifyPlugin = async ({ $ }) => {
  const notifyScript = `${process.env.HOME}/.cc-notify/bin/smart-notify.sh`

  const notify = async (args) => {
    try {
      const [source, event, kind, title, body, priority] = args
      await $`${notifyScript} --source ${source} --event ${event} --kind ${kind} --title ${title} --body ${body} --priority ${priority}`
    } catch {
      // 通知失败不应影响 OpenCode 主流程
    }
  }

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "permission.asked":
          await notify([
            "opencode",
            "permission.asked",
            "intervention",
            "⚠️ 需要权限确认",
            "OpenCode 正在等待你的权限确认",
            "high",
          ])
          break
        case "session.error":
          await notify([
            "opencode",
            "session.error",
            "error",
            "❌ OpenCode 出现错误",
            "OpenCode 会话发生错误，请回来看一下",
            "normal",
          ])
          break
        case "session.idle":
          await notify([
            "opencode",
            "session.idle",
            "terminal",
            "✅ OpenCode 当前已空闲",
            "请查看当前会话结果",
            "low",
          ])
          break
      }
    },
  }
}
