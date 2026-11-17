import { defineCustomElement } from 'vue'
import Widget from './Widget.ce.vue'

const UaaChat = defineCustomElement(Widget)
if (!customElements.get('uaa-chat')) customElements.define('uaa-chat', UaaChat)

// <script src="uaa-widget.js" data-site-key data-api-url data-api-key> mounts it automatically
function _mountWidget() {
  if (document.querySelector('uaa-chat')) return
  const s = document.currentScript || document.querySelector('script[data-site-key]') || document.querySelector('script[src*="uaa-widget"]')
  if (s && s.dataset && s.dataset.siteKey) {
    const el = document.createElement('uaa-chat')
    el.setAttribute('site-key', s.dataset.siteKey)
    if (s.dataset.apiUrl) el.setAttribute('api-url', s.dataset.apiUrl)
    if (s.dataset.apiKey) el.setAttribute('api-key', s.dataset.apiKey)
    if (s.dataset.botEnabled !== undefined) el.setAttribute('bot-enabled', s.dataset.botEnabled)
    if (s.dataset.bot !== undefined) el.setAttribute('bot', s.dataset.bot)
    if (s.dataset.botMode !== undefined) el.setAttribute('bot-mode', s.dataset.botMode)
    if (s.dataset.botChat !== undefined) el.setAttribute('bot-chat', s.dataset.botChat)
    const add = () => { if (document.body && !document.querySelector('uaa-chat')) document.body.appendChild(el) }
    document.body ? add() : document.addEventListener('DOMContentLoaded', add)
  }
}
_mountWidget()
if (!document.querySelector('uaa-chat')) {
  document.addEventListener('DOMContentLoaded', _mountWidget)
  window.addEventListener('load', _mountWidget)
}
if (typeof window !== 'undefined') {
  window.setUaaBotEnabled = function(enabled) {
    window.UAA_BOT_ENABLED = Boolean(enabled)
    const el = document.querySelector('uaa-chat')
    if (el) {
      el.setAttribute('bot-enabled', String(enabled))
      el.setAttribute('bot', String(enabled))
    }
  }
}
export { UaaChat }
