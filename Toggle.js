let toggle = 0;

window.addEventListener('DOMContentLoaded', () => customElements.define('toggle-', class extends HTMLElement {
    constructor() {
        super();
        this.type = "checkbox";
        const id = 'toggle-' + toggle;

        const wrapper = document.createElement('div');
        wrapper.innerHTML = `
        <label for="${id}" class="flex items-center cursor-pointer">
            <div class="relative">
                <input id="${id}" type="checkbox" class="hidden" />
                <div class="w-10 h-4 bg-gray-400 rounded-full shadow-inner"></div>
                <div class="toggle-dot absolute w-6 h-6 bg-white rounded-full shadow inset-y-0 left-0"></div>
            </div>
            <div class="ml-3 text-gray-700 font-medium">${this.getAttribute('title')}</div>
        </label>`;

        this.appendChild(wrapper);
    }
}));
