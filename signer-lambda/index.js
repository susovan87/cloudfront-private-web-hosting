// Importing required modules
const { getSignedCookies } = require("@aws-sdk/cloudfront-signer");
const { OAuth2Client } = require('google-auth-library');
const querystring = require('node:querystring');
const { Buffer } = require('node:buffer');

// Initializing OAuth2Client
const oAuth2Client = new OAuth2Client();

// Fetching environment variables
const googleClientId = process.env.GOOGLE_CLIENT_ID;
const privateKey = Buffer.from(process.env.CLOUDFRONT_KEYPAIR_PRIVATE_KEY, 'base64');
const keyPairId = process.env.CLOUDFRONT_KEYPAIR_ID;
const url = `https://${process.env.CLOUDFRONT_DOMAIN}/*`;
const maxSessionDuration = parseInt(process.env.MAX_SESSION_DURATION);
const emailDomain = process.env.EMAIL_DOMAIN;

// Constants
const CONTENT_TYPE = 'content-type';
const APPLICATION_FORM = 'application/x-www-form-urlencoded';
const POST = 'POST';
const AUTH_VALIDATE = '/auth/validate';

/**
 * AWS Lambda handler function.
 *
 * @param {Object} event - The event object.
 * @param {Object} context - The context object.
 * @returns {Object} The response object.
 */
exports.handler = async function (event, context) {
    const { headers, requestContext, body, isBase64Encoded, queryStringParameters } = event;
    const { http } = requestContext;
    const contentType = headers[CONTENT_TYPE] || headers[CONTENT_TYPE.toUpperCase()] || '';
    const httpMethod = http.method.toUpperCase();
    const userIp = getUserIp(headers);
    const requestPath = http.path;
    const callback = queryStringParameters && queryStringParameters.cb || '/index.html';

    if (isAuthRequest(contentType, httpMethod, requestPath)) {
        let decodedBody = decodeBody(body, isBase64Encoded);
        try {
            await verifyGoogleToken(decodedBody.credential);
            const cookieHeader = generateCookieHeaders(maxSessionDuration, userIp);
            return createResponse("302", callback, cookieHeader);
        } catch (error) {
            console.error(error);
            return createResponse("401", null, null, "<h1>Unauthorized</h1>");
        }
    }

    return createResponse("307", "/auth/login.html");
}

/**
 * Extracts user IP from headers.
 *
 * @param {Object} headers - The headers object.
 * @returns {string} The user IP.
 */
function getUserIp(headers) {
    return headers['cloudfront-viewer-address'] && headers['cloudfront-viewer-address'].split(':')[0] || headers['x-forwarded-for'];
}

/**
 * Checks if the request is an authentication request.
 *
 * @param {string} contentType - The content type of the request.
 * @param {string} httpMethod - The HTTP method of the request.
 * @param {string} requestPath - The request path.
 * @returns {boolean} True if it is an authentication request, false otherwise.
 */
function isAuthRequest(contentType, httpMethod, requestPath) {
    return contentType.toLowerCase() === APPLICATION_FORM && httpMethod === POST && requestPath === AUTH_VALIDATE;
}

/**
 * Decodes the request body.
 *
 * @param {string} body - The request body.
 * @param {boolean} isBase64Encoded - Flag indicating if the body is Base64 encoded.
 * @returns {Object} The decoded body.
 */
function decodeBody(body, isBase64Encoded) {
    let decodedBody = isBase64Encoded ? Buffer.from(body, 'base64').toString('utf8') : body;
    return querystring.decode(decodedBody);
}

/**
 * Creates a response object.
 *
 * @param {string} statusCode - The status code.
 * @param {string} [location=null] - The location header.
 * @param {string} [cookies=null] - The cookies.
 * @param {string} [body=null] - The response body.
 * @returns {Object} The response object.
 */
function createResponse(statusCode, location = null, cookies = null, body = null) {
    let response = {
        headers: {},
        statusCode: statusCode
    };

    if (location) {
        response.headers["Location"] = location;
    }

    if (cookies) {
        response.cookies = cookies;
    }

    if (body) {
        response.headers["Content-Type"] = "text/html";
        response.body = body;
    }

    return response;
}

/**
 * Generates cookie headers.
 *
 * @param {number} maxSessionDuration - The maximum session duration.
 * @param {string} userIp - The user's IP address.
 * @returns {string[]} The cookie headers.
 */
function generateCookieHeaders(maxSessionDuration, userIp) {
    // Create the policy object.
    const policy = {
        Statement: [{
            Resource: url,
            Condition: {
                DateLessThan: {
                    'AWS:EpochTime': Math.round(Date.now() / 1000) + maxSessionDuration
                },
                IpAddress: {
                    "AWS:SourceIp": userIp
                }
            }
        }]
    };

    // Create the sign parameters.
    const signParam = { keyPairId, privateKey, policy: JSON.stringify(policy) };

    // Get the signed cookies.
    const cookies = getSignedCookies(signParam);

    // Create the cookie headers.
    const cookieHeader = Object.entries(cookies).map(([key, value]) => (`${key}=${value}; Path=/; Secure; HttpOnly`));

    return cookieHeader;
}

/**
 * Verifies the Google token.
 *
 * @param {string} token - The Google token.
 * @returns {Promise<boolean>} A promise that resolves to true if the token is valid, false otherwise.
 */
async function verifyGoogleToken(token) {
    const ticket = await oAuth2Client.verifyIdToken({
        idToken: token,
        audience: googleClientId
    });

    const payload = ticket.getPayload();
    if (isPayloadValid(payload)) {
        console.log(`User ${payload['email']} authenticated successfully!`)
        return true;
    }

    console.error(`Unauthorized payload: ${JSON.stringify(payload, null, 2)}`);
    throw new Error(`Unauthorized access attempt with email: ${payload['email']}`);
}

/**
 * Checks if the payload is valid.
 *
 * @param {Object} payload - The payload object.
 * @returns {boolean} True if the payload is valid, false otherwise.
 */
function isPayloadValid(payload) {
    if (!emailDomain && payload && payload['email_verified']) {
        return true;
    } else if (payload && payload['hd'] === emailDomain && payload['email_verified']) {
        return true;
    }
    return false;
}