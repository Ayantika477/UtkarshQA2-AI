import { LightningElement, track, wire } from 'lwc';
import saveExpenseData from '@salesforce/apex/NewExpenseFormController.saveExpenseData';
import getEligibility from '@salesforce/apex/NewExpenseFormController.getEligibility';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class NewExpenseForm extends LightningElement {

    @track isSaving = false;
    @track isLoadingEligibility = true;
    @track eligibility = null;
    @track eligibilityError = null;

    // UIL eligibility matrix city classification (w.e.f. 01 Jul 2026)
    tier1Cities = [
        'Mumbai', 'Bangalore', 'Bengaluru', 'Chennai', 'Kolkata', 'Hyderabad',
        'Pune', 'Ahmedabad', 'Guwahati', 'Delhi', 'Gurugram', 'Gurgaon', 'Noida', 'NCR'
    ];

    tier2Cities = [
        'Jaipur', 'Lucknow', 'Chandigarh', 'Indore', 'Surat', 'Nagpur', 'Coimbatore',
        'Kochi', 'Visakhapatnam', 'Vadodara', 'Bhopal', 'Ludhiana', 'Nashik', 'Rajkot',
        'Madurai', 'Varanasi', 'Mysore', 'Mysuru', 'Patna', 'Ranchi', 'Thiruvananthapuram',
        'Jodhpur', 'Amritsar', 'Kanpur', 'Agra', 'Vijayawada', 'Jamshedpur', 'Faridabad',
        'Ghaziabad', 'Srinagar', 'Jammu', 'Aizawl', 'Goa', 'Pondicherry', 'Puducherry'
    ];

    @track formData = {
        startDate: null,
        endDate: null,
        city: '',
        cityTier: ''
    };

    @track expenseTypeOptions = [];
    @track airClassOptions = [];
    @track trainClassOptions = [];
    @track roadwayOptions = [];
    @track ownVehicleOptions = [];

    @track lineDataMap = {};
    @track selectedTypesArray = [];

    @wire(getEligibility)
    wiredEligibility({ error, data }) {
        this.isLoadingEligibility = false;
        if (data) {
            this.eligibility = data;
            this.eligibilityError = null;
            this.buildOptionsFromEligibility();
        } else if (error) {
            this.eligibility = null;
            this.eligibilityError = this.getErrorMessage(error);
            this.expenseTypeOptions = [];
            this.showToast('Error', this.eligibilityError, 'error');
        }
    }

    get hasSelectedTypes() {
        return this.selectedTypesArray.length > 0;
    }

    get hasEligibility() {
        return this.eligibility != null;
    }

    get isSubmitDisabled() {
        return this.isSaving || !this.hasEligibility || this.isLoadingEligibility;
    }

    get allCitySuggestions() {
        return [...this.tier1Cities, ...this.tier2Cities];
    }

    get tripDays() {
        if (!this.formData.startDate || !this.formData.endDate) {
            return 0;
        }
        const start = new Date(this.formData.startDate);
        const end = new Date(this.formData.endDate);
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end < start) {
            return 0;
        }
        const msPerDay = 24 * 60 * 60 * 1000;
        return Math.floor((end - start) / msPerDay) + 1;
    }

    get foodingDailyLimit() {
        return this.getDailyLimit('Fooding');
    }

    get lodgingDailyLimit() {
        return this.getDailyLimit('Lodging');
    }

    get foodingMaxAllowed() {
        return this.foodingDailyLimit * this.tripDays;
    }

    get lodgingMaxAllowed() {
        return this.lodgingDailyLimit * this.tripDays;
    }

    get foodingLimitLabel() {
        if (!this.eligibility || !this.formData.cityTier || this.tripDays <= 0) {
            return 'Enter travel dates and city to see Fooding limit';
        }
        return `Max allowed: ₹${this.foodingMaxAllowed} (₹${this.foodingDailyLimit}/day × ${this.tripDays} days)`;
    }

    get lodgingLimitLabel() {
        if (!this.eligibility || !this.formData.cityTier || this.tripDays <= 0) {
            return 'Enter travel dates and city to see Lodging limit';
        }
        return `Max allowed: ₹${this.lodgingMaxAllowed} (₹${this.lodgingDailyLimit}/day × ${this.tripDays} days)`;
    }

    buildOptionsFromEligibility() {
        const e = this.eligibility;
        if (!e) {
            this.expenseTypeOptions = [];
            return;
        }

        const options = [
            { label: 'Fooding', value: 'Fooding' },
            { label: 'Lodging', value: 'Lodging' }
        ];

        this.airClassOptions = [];
        if (e.Air_Business_Class__c) {
            this.airClassOptions.push({ label: 'Business', value: 'Business' });
        }
        if (e.Air_Economy_Class__c) {
            this.airClassOptions.push({ label: 'Economy', value: 'Economy' });
        }
        if (this.airClassOptions.length > 0) {
            options.push({ label: 'Air', value: 'Air' });
        }

        this.trainClassOptions = [];
        if (e.Train_1AC__c) this.trainClassOptions.push({ label: '1AC', value: '1AC' });
        if (e.Train_2AC__c) this.trainClassOptions.push({ label: '2AC', value: '2AC' });
        if (e.Train_3AC__c) this.trainClassOptions.push({ label: '3AC', value: '3AC' });
        if (e.Train_Sleeper__c) this.trainClassOptions.push({ label: 'Sleeper', value: 'Sleeper' });
        if (this.trainClassOptions.length > 0) {
            options.push({ label: 'Train', value: 'Train' });
        }

        this.roadwayOptions = [];
        if (e.Ola_Uber_Taxi__c) {
            this.roadwayOptions.push({ label: 'OLA/UBER/TAXI', value: 'OLA/UBER/TAXI' });
        }
        if (e.Car_Rental__c) {
            this.roadwayOptions.push({ label: 'Car Rental', value: 'Car Rental' });
        }
        if (e.Auto__c) {
            this.roadwayOptions.push({ label: 'Auto', value: 'Auto' });
        }
        if (e.Bus__c) {
            this.roadwayOptions.push({ label: 'Bus', value: 'Bus' });
        }
        if (this.roadwayOptions.length > 0) {
            options.push({ label: 'Roadways', value: 'Roadways' });
        }

        this.ownVehicleOptions = [];
        if (e.Own_2_Wheeler_Rate_per_KM__c != null && e.Own_2_Wheeler_Rate_per_KM__c > 0) {
            this.ownVehicleOptions.push({ label: '2-Wheeler', value: '2-Wheeler' });
        }
        if (e.Own_4_Wheeler_Rate_per_KM__c != null && e.Own_4_Wheeler_Rate_per_KM__c > 0) {
            this.ownVehicleOptions.push({ label: '4-Wheeler', value: '4-Wheeler' });
        }
        if (this.ownVehicleOptions.length > 0) {
            options.push({ label: 'Own Vehicle', value: 'Own Vehicle' });
        }

        this.expenseTypeOptions = options;
    }

    getDailyLimit(expenseType) {
        if (!this.eligibility || !this.formData.cityTier) {
            return 0;
        }
        const e = this.eligibility;
        const tier = this.formData.cityTier;
        if (expenseType === 'Fooding') {
            if (tier === 'Tier 1') return Number(e.Fooding_Tier_1__c || 0);
            if (tier === 'Tier 2') return Number(e.Fooding_Tier_2__c || 0);
            return Number(e.Fooding_Tier_3__c || 0);
        }
        if (expenseType === 'Lodging') {
            if (tier === 'Tier 1') return Number(e.Lodging_Tier_1__c || 0);
            if (tier === 'Tier 2') return Number(e.Lodging_Tier_2__c || 0);
            return Number(e.Lodging_Tier_3__c || 0);
        }
        return 0;
    }

    getOwnVehicleRate(vehicleType) {
        if (!this.eligibility || !vehicleType) {
            return 0;
        }
        if (vehicleType === '2-Wheeler') {
            return Number(this.eligibility.Own_2_Wheeler_Rate_per_KM__c || 0);
        }
        if (vehicleType === '4-Wheeler') {
            return Number(this.eligibility.Own_4_Wheeler_Rate_per_KM__c || 0);
        }
        return 0;
    }

    resolveCityTier(inputCity) {
        if (!inputCity || !inputCity.trim()) {
            return '';
        }
        const city = inputCity.trim().toLowerCase();
        if (this.tier1Cities.some(c => c.toLowerCase() === city)) {
            return 'Tier 1';
        }
        if (this.tier2Cities.some(c => c.toLowerCase() === city)) {
            return 'Tier 2';
        }
        return 'Tier 3';
    }

    handleInputChange(event) {
        this.formData[event.target.name] = event.target.value;
        this.refreshLimitLabelsOnRows();
    }

    handleCityChange(event) {
        const inputCity = event.target.value;
        this.formData.city = inputCity;
        this.formData.cityTier = this.resolveCityTier(inputCity);
        this.refreshLimitLabelsOnRows();
    }

    refreshLimitLabelsOnRows() {
        // Re-attach limit labels so template reacts when dates/tier change
        Object.keys(this.lineDataMap).forEach(type => {
            this.lineDataMap[type].forEach((row, index) => {
                this.applyRowHints(type, index);
            });
        });
        this.updateIterableArray();
    }

    applyRowHints(type, index) {
        const row = this.lineDataMap[type][index];
        if (!row) return;

        // Fooding/Lodging limits shown once at group level via groupLimitLabel
        if (type === 'Own Vehicle') {
            const rate = this.getOwnVehicleRate(row.selectedValue);
            row.ratePerKm = rate;
            if (row.selectedValue && rate > 0) {
                const km = Number(row.distanceKm || 0);
                if (km > 0) {
                    row.limitLabel = `Rate: ₹${rate}/KM · Max allowed: ₹${rate * km}`;
                } else {
                    row.limitLabel = `Rate: ₹${rate}/KM · Enter distance to see max`;
                }
                row.showLimitLabel = true;
            } else {
                row.limitLabel = 'Select vehicle type to see rate';
                row.showLimitLabel = true;
            }
        } else {
            row.showLimitLabel = false;
            row.limitLabel = '';
        }
    }

    handleTypeSelection(event) {
        const type = event.target.value;
        const isChecked = event.target.checked;

        if (isChecked) {
            this.lineDataMap[type] = [this.createNewRow(type)];
        } else {
            delete this.lineDataMap[type];
        }
        this.updateIterableArray();
    }

    createNewRow(type) {
        const row = {
            id: Date.now() + Math.random().toString(),
            name: type,
            amount: null,
            selectedValue: '',
            distanceKm: null,
            ratePerKm: 0,
            base64Data: null,
            fileName: '',
            limitLabel: '',
            showLimitLabel: false,
            isAir: type === 'Air',
            isTrain: type === 'Train',
            isRoadways: type === 'Roadways',
            isOwnVehicle: type === 'Own Vehicle',
            isFoodingOrLodging: type === 'Fooding' || type === 'Lodging'
        };
        return row;
    }

    handleAddMoreRow(event) {
        const type = event.target.dataset.type;
        this.lineDataMap[type].push(this.createNewRow(type));
        this.applyRowHints(type, this.lineDataMap[type].length - 1);
        this.updateIterableArray();
    }

    handleRemoveRow(event) {
        const type = event.target.dataset.type;
        const index = parseInt(event.target.dataset.index, 10);
        this.lineDataMap[type].splice(index, 1);
        this.updateIterableArray();
    }

    updateIterableArray() {
        this.selectedTypesArray = Object.keys(this.lineDataMap).map(key => {
            const items = this.lineDataMap[key].map((item, index) => {
                this.applyRowHints(key, index);
                return { ...this.lineDataMap[key][index] };
            });
            return {
                name: key,
                items,
                isFooding: key === 'Fooding',
                isLodging: key === 'Lodging',
                groupLimitLabel: key === 'Fooding'
                    ? this.foodingLimitLabel
                    : key === 'Lodging'
                        ? this.lodgingLimitLabel
                        : null
            };
        });
    }

    handleLineDataChange(event) {
        const { type, index } = event.target.dataset;
        this.lineDataMap[type][index].selectedValue = event.target.value;
        this.updateFileName(type, index);
        this.applyRowHints(type, index);
        this.updateIterableArray();
    }

    handleDistanceChange(event) {
        const { type, index } = event.target.dataset;
        this.lineDataMap[type][index].distanceKm = event.target.value;
        this.applyRowHints(type, index);
        this.updateIterableArray();
    }

    handleAmountChange(event) {
        const { type, index } = event.target.dataset;
        this.lineDataMap[type][index].amount = event.target.value;
    }

    handleFileUpload(event) {
        const { type, index } = event.target.dataset;
        const file = event.target.files[0];
        if (!file) return;

        // Supported types: images and PDF
        const isSupportedType =
            file.type.startsWith('image/') ||
            file.type === 'application/pdf';

        if (!isSupportedType) {
            this.showToast('Invalid File Format', 'Only image files or PDF files are supported.', 'error');
            event.target.value = '';
            return;
        }

        // 2 MB maximum
        const maxFileSize = 2 * 1024 * 1024;

        if (file.size > maxFileSize) {
            this.showToast('File Too Large', 'The file is too large. Please upload a smaller version (maximum 2 MB).', 'error');
            event.target.value = '';
            return;
        }

        let reader = new FileReader();
        reader.onload = () => {
            let base64 = reader.result.split(',')[1];
            this.lineDataMap[type][index].base64Data = base64;
            this.lineDataMap[type][index].originalExt = file.name.split('.').pop();
            this.updateFileName(type, index);
            this.updateIterableArray();
        };
        reader.readAsDataURL(file);
    }

    updateFileName(type, index) {
        let line = this.lineDataMap[type][index];
        if (!line.base64Data) return;

        let baseName = '';
        if (type === 'Fooding' || type === 'Lodging') {
            baseName = `${type.toLowerCase()} expense ${parseInt(index, 10) + 1}`;
        } else {
            let val = line.selectedValue ? ` ${line.selectedValue}` : '';
            baseName = `${type}${val} expense ${parseInt(index, 10) + 1}`;
        }
        line.fileName = baseName;
    }

    isEligibleSelection(type, selectedValue) {
        if (!selectedValue) return false;
        if (type === 'Air') {
            return this.airClassOptions.some(o => o.value === selectedValue);
        }
        if (type === 'Train') {
            return this.trainClassOptions.some(o => o.value === selectedValue);
        }
        if (type === 'Roadways') {
            return this.roadwayOptions.some(o => o.value === selectedValue);
        }
        if (type === 'Own Vehicle') {
            return this.ownVehicleOptions.some(o => o.value === selectedValue);
        }
        return true;
    }

    saveExpense() {
        if (!this.hasEligibility) {
            this.showToast('Error', this.eligibilityError || 'Eligibility not loaded', 'error');
            return;
        }

        if (!this.formData.startDate || !this.formData.endDate || !this.formData.city) {
            this.showToast('Error', 'Please fill all required travel details', 'error');
            return;
        }

        const today = new Date();
        today.setHours(0, 0, 0, 0);

        const endDate = new Date(this.formData.endDate + 'T00:00:00');

        const tenDaysAgo = new Date(today);
        tenDaysAgo.setDate(today.getDate() - 10);

        if (endDate < tenDaysAgo) {
            this.showToast('Error', 'An expense cannot be submitted beyond 10 days of expenditure.', 'error');
            return;
        }

        if (this.tripDays <= 0) {
            this.showToast('Error', 'Travel End Date must be on or after Start Date', 'error');
            return;
        }

        let flattenedLines = [];
        const typeTotals = { Fooding: 0, Lodging: 0 };

        for (let key in this.lineDataMap) {
            let linesForType = this.lineDataMap[key];

            for (let i = 0; i < linesForType.length; i++) {
                let item = linesForType[i];
                const rowLabel = `${item.name} (Row ${i + 1})`;
                const amount = Number(item.amount);

                if (!item.amount && item.amount !== 0) {
                    this.showToast('Error', `Please enter amount for ${rowLabel}`, 'error');
                    return;
                }

                if (key === 'Fooding' && !item.base64Data) {
                    this.showToast('Error', `Receipt is mandatory for ${rowLabel}`, 'error');
                    return;
                }

                if (item.isAir || item.isTrain || item.isRoadways || item.isOwnVehicle) {
                    if (!item.selectedValue) {
                        this.showToast('Error', `Please select class/type for ${rowLabel}`, 'error');
                        return;
                    }
                    if (!this.isEligibleSelection(key, item.selectedValue)) {
                        this.showToast('Error', `${item.selectedValue} is not allowed for your level (${rowLabel})`, 'error');
                        return;
                    }
                }

                if (key === 'Own Vehicle') {
                    const km = Number(item.distanceKm);
                    if (!km || km <= 0) {
                        this.showToast('Error', `Please enter Distance (KM) for ${rowLabel}`, 'error');
                        return;
                    }
                    const rate = this.getOwnVehicleRate(item.selectedValue);
                    const maxAllowed = rate * km;
                    if (amount > maxAllowed) {
                        this.showToast(
                            'Error',
                            `${rowLabel} amount ₹${amount} exceeds limit ₹${maxAllowed} (${km} KM × ₹${rate}/KM)`,
                            'error'
                        );
                        return;
                    }
                }

                if (key === 'Fooding' || key === 'Lodging') {
                    typeTotals[key] += amount;
                }

                flattenedLines.push({
                    expenseType: item.name,
                    amount: amount,
                    travelClass: (item.isAir || item.isTrain) ? item.selectedValue : null,
                    vehicleType: (item.isRoadways || item.isOwnVehicle) ? item.selectedValue : null,
                    distanceKm: item.isOwnVehicle ? Number(item.distanceKm) : null,
                    base64Data: item.base64Data,
                    fileName: item.fileName,
                    extension: item.originalExt
                });
            }
        }

        if (typeTotals.Fooding > 0) {
            if (!this.formData.cityTier || this.tripDays <= 0) {
                this.showToast('Error', 'Enter travel dates and city before claiming Fooding', 'error');
                return;
            }
            if (typeTotals.Fooding > this.foodingMaxAllowed) {
                this.showToast(
                    'Error',
                    `Total Fooding ₹${typeTotals.Fooding} exceeds limit ₹${this.foodingMaxAllowed}`,
                    'error'
                );
                return;
            }
        }

        if (typeTotals.Lodging > 0) {
            if (!this.formData.cityTier || this.tripDays <= 0) {
                this.showToast('Error', 'Enter travel dates and city before claiming Lodging', 'error');
                return;
            }
            if (typeTotals.Lodging > this.lodgingMaxAllowed) {
                this.showToast(
                    'Error',
                    `Total Lodging ₹${typeTotals.Lodging} exceeds limit ₹${this.lodgingMaxAllowed}`,
                    'error'
                );
                return;
            }
        }

        if (flattenedLines.length === 0) {
            this.showToast('Error', 'Please add at least one expense line amount', 'error');
            return;
        }

        const payload = {
            startDate: this.formData.startDate,
            endDate: this.formData.endDate,
            city: this.formData.city,
            cityTier: this.formData.cityTier,
            lines: flattenedLines
        };

        this.isSaving = true;
        saveExpenseData({ payload: JSON.stringify(payload) })
            .then((result) => {
                this.showToast('Success', `Expense claim ${result} created successfully`, 'success');
                this.resetForm();
            })
            .catch(error => {
                this.showToast('Error saving record', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    resetForm() {
        this.formData = { startDate: null, endDate: null, city: '', cityTier: '' };
        this.lineDataMap = {};
        this.selectedTypesArray = [];
        this.template.querySelectorAll('lightning-input').forEach(input => {
            if (input.type === 'toggle' || input.type === 'checkbox') {
                input.checked = false;
            } else {
                input.value = '';
            }
        });
    }

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        return error?.message || 'Unknown error';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}