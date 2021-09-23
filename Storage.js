const Storage = localStorage;

export default class LocalStorage {
    constructor(_Key) {
        this.Key = _Key;
    }

    Get() {
        try {
            return JSON.parse(Storage.getItem(this.Key));
        }
        catch(error) {
            console.warn(error);
            Storage.removeItem(this.Key);
        }
    }

    Set(data) {
        if(typeof data === 'object')
            data = JSON.stringify(data);

        Storage.setItem(this.Key, data);
    }
}
