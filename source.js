const organizationId = args[0];
const eventId = args[1];
const msgSender = args[2];
const percentageOff = args[3];
const quantityAvailable = args[4];

const resolveAddressToLensHandle = await Functions.makeHttpRequest({
    url: `https://api.lens.dev`,
    method: "POST",
    headers: {
        'Content-Type': 'application/json'
    },
    data: {
        query: `{
            profiles(request: { ownedBy: ["${msgSender}"] }) {
                items {
                    name
                }
            }
        }`,
    }
})

const lensHandle = resolveAddressToLensHandle.data.data.profiles.items[0].name;

console.log(lensHandle);

const discountCode = `DISCOUNT_CODE_${organizationId}_${eventId}_${lensHandle}`;

const createDiscount = await Functions.makeHttpRequest({
    url: `https://www.eventbriteapi.com/v3/organizations/${organizationId}/discounts/`,
    method: "POST",
    headers: {
        'Authorization': `Bearer ${secrets.OAUTH_KEY}`,
        'Content-Type': 'application/json'
    },
    data: {
        "discount": {
            "type": "coded",
            "code": discountCode,
            "percent_off": percentageOff, // "100"
            "event_id": eventId,
            "quantity_available": quantityAvailable // 1
        }
    }
});

if (createDiscount.status == 200) {
    console.log(createDiscount.data.code);
} else {
    console.error(createDiscount.message);
}


return Functions.encodeString(discountCode);
