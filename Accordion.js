class Accordion extends HTMLElement {
    constructor() {
        super();

        const wrapper = document.createElement('div');
        wrapper.classList.add('mb-4', 'rounded', 'shadow', 'bg-white', 'bg-opacity-75');
        wrapper.innerHTML = `
        <div class="tab w-full overflow-hidden border-t">
            <input class="absolute opacity-0 " id="input" type="checkbox" name="tabs">
            <label class="relative block p-5 pr-10 leading-normal cursor-pointer" for="input"></label>
            <div class="tab-content overflow-hidden border-l-2 bg-grey-lightest border-indigo leading-normal">
                <div class="p-5">${this.innerHTML}</div>
            </div>
        </div>`;
        wrapper.querySelector('label').textContent = this.getAttribute('title');
        this.innerHTML = '';
        this.appendChild(wrapper);
    }
}

class AccordionShadow extends Accordion {
    Link(shadow, href) {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = href;
        shadow.appendChild(link);
    }

    constructor() {
        super();

        const shadow = this.attachShadow({ mode: 'open' });
        const Link = this.Link.bind(this, shadow);

        const link = Array.prototype.find.call(document.querySelectorAll('link[rel="stylesheet"]'), ({ href }) => href.endsWith('tailwind.min.css'));
        link ?
            shadow.appendChild(link.cloneNode()) :
            Link('https://cdnjs.cloudflare.com/ajax/libs/tailwindcss/1.6.2/tailwind.min.css');
        Link('https://www.hwangsehyun.com/utils/Accordion.css');

        shadow.appendChild(this.firstElementChild);

    }

}

window.addEventListener('DOMContentLoaded', () => {
    customElements.define('accordion-', Accordion);
    customElements.define('accordion-shadow', AccordionShadow);
});
