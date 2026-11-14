import { defineCustomElement } from 'vue'
import Widget from './Widget.ce.vue'

const UaaChat = defineCustomElement(Widget)
if (!customElements.get('uaa-chat')) customElements.define('uaa-chat', UaaChat)

// <script src="uaa-widget.js" data-site-key data-api-url data-api-key> mounts it automatically
const s = document.currentScript
if (s && s.dataset.siteKey && !document.querySelector('uaa-chat')) {
  const el = document.createElement('uaa-chat')
  el.setAttribute('site-key', s.dataset.siteKey)
  el.setAttribute('api-url', s.dataset.apiUrl)
  el.setAttribute('api-key', s.dataset.apiKey)
  const add = () => document.body.appendChild(el)
  document.body ? add() : document.addEventListener('DOMContentLoaded', add)
}
export { UaaChat }
