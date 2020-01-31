---
layout: post
title: OAuth 2.0 and Open ID Connect 
author: ucelenli
---

Web apps in early 2000 were usually monolithic, having the frontend-backend coupled in the same application, with a server hosting the application end to end. The forms way of authorization was being done in the application, and the web user was authenticated using user agent cookies. 
{: .text-justify}

As time passes, websites naturally tried to do more. For example, sites like Facebook and Yelp wanted to invite your mail contacts into the site, and naively they asked for your email password on other providers to connect and get your contact list. But this was a horrible way of getting data. 
{: .text-justify}

![your email, password and blood of your first-born son please.](/blog/images/oauthoidc-1.png)

## The need for Delegated Authorization

In [2006](https://en.wikipedia.org/wiki/OAuth), guys from Twitter and Ma.gnolia discussed for a better way of sharing data across sites and they concluded there were no open standards for API delegation. Soon enough there was a discussion group with Google joining and in 2010 OAuth version 1.0 was released. It was a framework based on digital signatures. 
{: .text-justify}

However, OAuth 1.0 required crypto-implementation and crypto-interoperability. Due to the cryptographic requirements of the protocol, developers were forced to find, install and configure libraries which became difficult to implement.
{: .text-justify}

In October 2012 came OAuth 2.0, which is a complete rewrite of its ancestor. OAuth 2.0 represents years of discussions between a wide range of companies and individuals including Yahoo!, Facebook, Salesforce, Microsoft, Twitter, Deutsche Telekom, Intuit, Mozilla and Google.
{: .text-justify}

## OAuth 2.0 with an example

Let’s imagine we have an ASP web app called fizzbuzz. We need to let google know about it, thus a one-time setup must be made. Once the registration is done, we have a client id and a client secret on hand, which are used on some scenarios. 
{: .text-justify}

Client secret is a sensitive data and must be stored on client securely. It will be used to prove that we are the correct client when we’ll exchange authorization codes with access tokens.  The key elements of OAuth 2.0 are as follows. 
{: .text-justify}

**Resource Owner**; the user who owns the credentials and data

**Client**; is the application, who will ask for the delegation and access remote data.

**Authorization Server**; is the authority who can grant access to client.

**Resource Server**; (sometimes same with Authorization Server) is the resource that client wants access to.

**Authorization Code**; is a short-lived token, sent to client after authorization. It is used for exchange with an access token.

**Access Token**; is a key for client to access resource server that is provided by the authorization server.
Authorization Grant; the act of authorizing client against an authorization server. 

## Scopes and Access Granularity

When asking for permissions, it’s never all or nothing. It is a good idea to declare what kind of operations are permitted to client when asking for delegated access, and OAuth exactly does that with scopes. 
{: .text-justify}

Scopes are the list of privileges we’re asking for when doing a request. And consent screens make sure what is being granted. The list of scopes that can be requested is defined by the Authorization Server and all requests should be done accordingly. Here is a request specifically asking permission for user profile, contacts and calendar access.
{: .text-justify}

```
{
	client_id = ‘fizzbuzz’    
	redirect_uri = ‘https://fizzbuzz.com/callback’
	response_type = ‘code’
	scope = ‘profile contacts calendar’
}
```

## Channels

In networking scenarios, there are two ways systems reach each other.  Front Channel and Back Channel. 
 > “Front-channel communication is when the communications between two or more parties which are observable within the protocol. Back-channel Communication is when the communications are NOT observable to at least one of the parties within the protocol.” 
{: .text-justify}

In simple terms, *Front Channel Communication* is when requests are communicated via the User Agent and *Back Channel Communication* is when requests are communicated using direct network links between servers. 
{: .text-justify}

Back Channel communication relies on mutually authenticated TLS (Transport Layer Security) for end-to-end security as the communication is point-to-point, thus considered more secure.
{: .text-justify}

## Flows

OAuth 2.0 supports different Authentication and Authorization flows (called grants) which serve different architectures. Each flow defines the request-response chain and between the client and authorization authority.
{: .text-justify}

Most common ones are

- Authorization Code Flow (front channel + back channel) 
- Implicit Flow (front channel only)

Also, other flows exist, but not used in web apps.
- Client Credentials Flow (back channel only)
- Device Authorization Flow (for devices with no browser or limited input capability, seen to be used on Apple Tv)
- Resource Owner Password Credentials (back channel only)

## Authorization Code Flow

Authorization Flow uses both front-channel and back-channel. Once authorized (with consent) the request is redirected back to a registered endpoint with the Authorization Code. Then this code is exchanged with an Access Token thru back channel. Then the app uses access token for resource access.
{: .text-justify}

Here we imagine a web application with backend, registered to google and anyone using a google account can authenticate against account.google.com to grant access and get her contact list into the application. 
{: .text-justify}

![Authorization Code Flow](/blog/images/oauthoidc-2.png)

- [1] On fizzbuzz, when user clicks on a button named “login with google”, the app is redirected to accounts.google.com with the following;
```
{
	client_id = ‘fizzbuzz’
	redirect_uri = ‘https://fizzbuzz.com/callback’
	response_type= ‘code’
	scope = ‘profile contacts calendar’
}
```

- [2] We land on an authentication page where we are asked for credentials. When we proceed with correct email and password, we are taken to a consent page, making sure what permission we are granting for what client.

- [3] If all accepted and done, user is redirected to the fizzbuzz app with an Authorization Code. This code is not for accessing data. It is for getting an Access Token from the authority, so that we can access resources we permitted just ago.

- [4] Now fizzbuzz must handle the incoming request with the Authorization Code and make a new request to Authorization Server to exchange this code, and the client secret to obtain an Access Token.

- [5] Authorization server checks if the Authorization Code is valid and not expired. If so, our request comes back with another callback request including an Access Token which will be used for further resource requests.

- [6] Now the user is Authorized and has access to the resources provided by the Resource Server.

 
## Implicit Flow

Back in early 2000 browser-based apps were restricted to sending requests to their server’s origin only. Because of the [Same Origin Policy](https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy), there was no way to call an authorization server’s token endpoint at a different host. 
{: .text-justify}

Thus, frontend applications were not able to get an access token from another origin using Authorization Code flow, and [Cross Origin Resource Sharing](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) was not commonly available (it was accepted as a W3C Recommendation in 2014). Even if it was available, SPA’s have the problem of keeping a client secret securely, which is another limitation.
{: .text-justify}

For these reasons, Implicit Flow was mainly designed for SPA’s and JavaScript applications with no backend channel.  
{: .text-justify}

![Implicit Flow](/blog/images/oauthoidc-3.png)

- [1] User creates an authorization request on Authorization Server and taken to a login page.
```
{
	client_id = ‘fizzbuzz’
	redirect_uri = ‘https://fizzbuzz.com/callback’
	response_type= ‘token’
	scope = ‘profile contacts calendar’
}
```
- [2] User enters credentials
- [3] (optionally taken to a consent page)
- [4] Authorization Server makes a callback to the callback URL with an issued Access Token.
- [5] User uses the Access Token until it expires to access resources.

The implicit flow looks simpler and less requests involved, but this has also some security implications. 

On November 2018, IETF’s OAuth working group released an draft RFC called  [OAuth 2.0 Security Best Current Practice](https://tools.ietf.org/html/draft-ietf-oauth-security-topics-09) , saying that;

> “The implicit grant (response type “token”) and other response types causing the authorization server to issue access tokens in the authorization response are vulnerable to access token leakage and access token replay … In order to avoid these issues, Clients SHOULD NOT use the implicit grant and any other response type causing the authorization server to issue an access token in the authorization response.”

Today, the security flaws known for Implicit Flow is as follows;

-	[Confused Deputy problem](https://stackoverflow.com/questions/17241771/how-and-why-is-google-oauth-token-validation-performed/17439317#17439317). The client app must check if the Access token provided belongs to your client.
-	If access token is stored on Local Storage it may be stolen via [XSS attack](https://medium.com/redteam/stealing-jwts-in-localstorage-via-xss-6048d91378a0). 
-	[Session fixation issues](https://hueniverse.com/explaining-the-oauth-session-fixation-attack-aa759250a0e7).
-	Possible [token leakage with referrer header](https://dzone.com/articles/is-your-site-leaking-password-reset-links). 

# Some more history

When Auth 2.0 was released in 2012, Facebook reached its first 1 billion users, becoming the attention centre for all the web. Everyone wanted their share with the Facebook userbase, and put a Facebook Login button into their website. 
{: .text-justify}

![first billion is the hardest they say.](/blog/images/oauthoidc-4.png)



# Authentication and Authorization

With the social media rise, OAuth 2.0 became popular and started being used widely, but not exactly for the right reason. Apart from Delegated Authorization, OAuth 2.0 was being used for Simple Logins, One Click Sign On across multiple sites (Facebook Login), Mobile App Logins and so on.
{: .text-justify}

![`and what you are doing in my backyard?`](/blog/images/oauthoidc-5.png)

OAuth was designed for Delegate Authorization, but it was being used for Authentication as well. But it was not the right tool for the problem. One can even say this is against single responsibility principle.
{: .text-justify}

OAuth 2.0 had no standard way of defining the user, it just dealed with permissions. So, each OAuth provider implemented their own ways of defining the user within the protocol, but it was not standard.
{: .text-justify}

# Open ID Connect

A good analogy of an Access Token is an hotel key. Once you check into a hotel you are handed a key. The key does not know who you are, or how much you paid. It just lets you into your room and stops doing that when expires. 
{: .text-justify}

To solve this problem, yet another protocol arrived. Open ID Connect (OIDC for short) is a protocol, or an extension on top of OAuth 2.0. Its purpose is to standardize the Authentication part, so the OAuth implementations looked alike.
{: .text-justify}

OIDC uses the scopes feature of an OAuth request, using the id_token scope, which actually means when we authorize, we also want the User Information next to the Access Token. 
{: .text-justify}

Id token is a long string in a specific format called JWT (JSON Web Token). It is represented as a sequence of base64url encoded values that are separated by period characters. It has 3 parts header, payload and signature. 
{: .text-justify}

> eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6Ik
pvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ
.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c

The signature part has the cryptographic hash of the token. Without doing any additional requests, we can verify that the token is not tampered with and it is genuinely issued by the Authorization Server.
{: .text-justify}

![jwt inside](/blog/images/oauthoidc-6.png)

And if the id_token (User information token) does not have enough details for the user, we can always make a request to /userinfo endpoint on the Authorization Provider to get more custom information regarding the domain. With the use of Open ID Connect, we separate Authentication and Authorization in a standardized way. 
{: .text-justify}

# Authorization Code Flow with Proof Key for Code Exchange (PKCE) 

SPA’s and mobile applications cannot securely store a client secret. Mobile apps can be decompiled, SPA is all JavaScript that runs in browser, as all it has is front channel it will expose the client secret.
{: .text-justify}

To mitigate this, OAuth 2.0 provides a version of the Authorization Code Flow which makes use of a Proof Key for Code Exchange. (PKCE was originally created for mobile and native applications because, at the time, both browsers and most providers were not capable of supporting PKCE. That is no longer the case.)
{: .text-justify}

The PKCE-enhanced Authorization Code Flow introduces a secret created by the calling application that can be verified by the authorization server; this secret is called the Code Verifier. Additionally, the calling app creates a transform value of the Code Verifier called the Code Challenge (which is a one-way SHA256 hash of the Code Verifier) and sends this value over HTTPS to retrieve an Authorization Code. No need to securely store a secret anymore.
{: .text-justify}

This way, a malicious attacker can only intercept the Authorization Code, and they cannot exchange it for a token without the Code Verifier. 
{: .text-justify}

![code flow with pkce](/blog/images/oauthoidc-7.png)

- [1] Before the authorization request, the client first creates what is known as a Code Verifier. This is a cryptographically random string using the characters A-Z, a-z, 0-9, and the punctuation characters, between 43 and 128 characters long.

- [2] Once the app has generated the code verifier, it uses that to create the code challenge. The code challenge is a baseurl encoded string of the SHA256 hash of the code verifier. 

- [3] Now that the client has a code challenge string, it includes that and a parameter that indicates which method was used to generate the challenge along with the standard parameters of the authorization request. 
This means a complete authorization request will include the following parameters.
```
{
	client_id = ‘fizzbuzz’
	redirect_uri = ‘https://fizzbuzz.com/callback’
	response_type= ‘code’
	scope = ‘profile contacts calendar’
	code_challenge = ’<The code challenge string>’
	code_challenge_method = S256 
}
```

- [4] Authorization server saves the code challenge for later use, redirects to a consent page if needed.

- [5] Authorization server calls the callback URL with an Authorization Code.

- [6] Client makes another request using the Authorization Code and Code Verifier.

- [7] Authorization Server validates the code challenge against the code verifier, and if validated, returns an Access Token (and an ID token if requested) to the callback endpoint. 

- [8] Now client has a validated Access Token for accessing resources.
 

## Conclusion
As SPA’s are rapidly used and as the nature of the apps are similar to mobile applications, it is suggested that the Authorization Code Flow with PKCE is to be used for Authorization and Authentication.
{: .text-justify}

Since the authorization can be denied for requests that do not contain a code challenge. This is really the only way to allow public clients to have a secure authorization flow without using the client secret.
{: .text-justify}

## References

- https://www.oauth.com/oauth2-servers/pkce/
- https://www.oauth.com/oauth2-servers/pkce/authorization-request/
- https://auth0.com/docs/flows/concepts/auth-code-pkce
- https://brockallen.com/2019/01/03/the-state-of-the-implicit-flow-in-oauth2/
- https://www.youtube.com/watch?v=996OiexHze0
- https://developer.okta.com/blog/2019/08/22/okta-authjs-pkce
- https://medium.com/oauth-2/why-you-should-stop-using-the-oauth-implicit-grant-2436ced1c926
- https://tools.ietf.org/html/rfc7636
- https://tools.ietf.org/html/draft-ietf-oauth-security-topics-09
