---
layout: post
title: About Cryptography 
author: ikoc
---

In this post , I will try to explain what is Cryptography , what are the main feautures of Cryptography in general aspects.Then I will show you sample application for secure data transfer.

* TOC
{:toc}

# What is Cryptography?

When we investigate the word Cryptography it can be split into two words crypto and graphy which can be interpreted as secret writing. So in briefly the main goal and usage of Cryptography is creating secure communication line(in unsafe areas).With Encryption and Decryption functionalities,cryptography can give you this protected message line. In Cryptography lessons/tutorial we can see the names like [Alice, Bob and Eve](https://en.wikipedia.org/wiki/Alice_and_Bob) in everywhere (although in this post). Alice and Bob are friends who are sending messages over unsecure medium and Eve is trying to eavesdropping them.

##### Encryption Process
* Plain Text + key -> Algorithm -> Cipher text
##### Decryption Process
* Cipher Text + key -> Algorithm -> Plain text

There are five primary functions of cryptography:
1. Privacy/confidentiality: Ensuring that no one can read the message except the intended receiver.
2. Authentication: The process of proving one's identity.
3. Integrity: Assuring the receiver that the received message has not been altered in any way from the original.
4. Non-repudiation: A mechanism to prove that the sender really sent this message.
5. Key exchange: The method by which crypto keys are shared between sender and receiver. 

# Types of Cryptographic Algorithms

There exist different types of algorithm for ensuring secure communication. 

#### 1. Secret Key Cryptography

It uses a single key for both encryption and decryption; also called symmetric encryption. Primarily used for privacy and confidentiality.Modern approaches of symmetric encryption are executed using algorithms such as RC4, AES, DES, 3DES, QUAD, Blowfish etc.

#### 2. Public Key Cryptography

It uses one key for encryption and another for decryption; also called asymmetric encryption. Primarily used for authentication, non-repudiation, and key exchange. Modern approaches of asymmetric encryption are executed using algorithms such as RSA, Diffie-Hellman, ECC, El Gamal, DSA etc.

#### 3. Hash Functions 

It uses a mathematical transformation to irreversibly "encrypt" information, providing a digital fingerprint. Primarily used for message integrity.
The ideal cryptographic hash function has the following main properties.
* Deterministic, meaning that the same message always results in the same hash.
* Quick to compute the hash value for any given message.
* Infeasible to generate a message that yields a given hash value
* Infeasible to find two different messages with the same hash value
* A small change to a message should change the hash value so extensively that the new hash value appears uncorrelated with the old hash value

# Usage of Cryptographic Algorithms

#### Symmetric vs. Asymmetric Cryptology

While comparing this two method we can use five primary function. 
* Privacy and Confidentiality can be both assured with two ways but Symmetric encryption is much more faster than Asymmetric encryption([Schneier](https://en.wikipedia.org/wiki/Bruce_Schneier) states “at least 1000 times faster”), so while encrypting large files Symmetric approach will be the first candidate to use. 
* Key exchange, in untrusted areas sharing key is important and this can be achieved easily with Asymmetric approach. Only public key will be shared. A person can send cipher text which encrypted with public key ,then only private key holder can decrypt it. 
* Authentication and Non-repudiation can be achieving by using Asymmetric approach.  
 
#### What is Digital Signature?

We can think that a digital signature is equivalent to handwritten signature. It has three purpopes.
1. Authentication
2. Non-repudiation
3. Integrity

Digital signatures are commonly used for software distribution, financial transactions, in emails etc.

##### Digital Signatures Usage Scenario
Think about Bob(sender) trying to send message to Alice(receiver)
1. Bob creates a key pair(Asymmetric key) , Public key and private key. Then share public key with Alice.
Both hash function and digital signature is used for the ensuring data integrity . Actualy digital signature use hash function to provide data integrity.
2. Bob creates a Digital Signature 
Bobs Plain Text Message -> Hash Algorithm -> Digest -> Private Key Encryption -> Digital Signature
3. Bob sends (Plain Text message + Digital Signature) to Alice.
4. Alice decrytps Digital signature and creates digest then uses hash function on plain text to create digest again. 
Digital Signature -> Public Key Decryption -> Digest
Plain Text -> Hash Algorithm -> Digest
5. Alice compares 2 digest. If they are same , She can understand that 
  -message sent from Bob
  -message integrity is not Broken

#### What is Diffie-Hellman Key Exchange? 
  Like we see in the name , this method invented for sharing key securely over a public channel. It was one of the first public-key protocols as originally conceptualized by Ralph Merkle and named after Whitfield Diffie and Martin Hellman.

##### Use Scenario
The simplest and the original implementation of the protocol uses the multiplicative group of integers modulo p, where p is prime, and g is a primitive root modulo p. These two values are chosen in this way to ensure that the resulting shared secret can take on any value from 1 to p–1. Here is an example of the protocol, with non-secret values and secret values.

1. Alice and Bob publicly agree to use a modulus p = 23 and base g = 5 (which is a primitive root modulo 23).
2. Alice chooses a secret integer a = 4, then sends Bob A = ga mod p
    A = 54 mod 23 = 4
3. Bob chooses a secret integer b = 3, then sends Alice B = gb mod p
    B = 53 mod 23 = 10
4. Alice computes s = Ba mod p
    s = 104 mod 23 = 18
5. Bob computes s = Ab mod p
    s = 43 mod 23 = 18
6. Alice and Bob now share a secret (the number 18).


#### What is Hybrid Cryptosystem

Like we mention above symmetric and asymmetric ciphers each have their own advantages and disadvantages.Symmetric ciphers are significantly faster  than asymmetric ciphers, but require all parties to somehow share a secret (the key). The asymmetric algorithms allow public key infrastructures and key exchange systems, but at the cost of speed.

Hybrid cryptosystem is one which combines the convenience of a public-key cryptosystem with the efficiency of a symmetric-key cryptosystem. 

A hybrid cryptosystem can be constructed using any two separate cryptosystems:
* A key encapsulation scheme, which is a public-key cryptosystem.
* A data encapsulation scheme, which is a symmetric-key cryptosystem.

All practical implementations of public key cryptography today employ the use of a hybrid system. Examples include the TLS protocol which uses a public-key mechanism for key exchange (such as RSA,Diffie-Hellman) and a symmetric-key mechanism for data encapsulation (such as AES). 

##### Python3 Example
To use this function you need to install pycryptodome library.
```
pip3 install pycryptodome
from Crypto.PublicKey import RSA
from Crypto.Cipher import AES
from Crypto.Cipher import PKCS1_OAEP
import binascii
import os
```

##### To encrypt a message addressed to Alice in a hybrid cryptosystem, Bob does the following:

1. Obtains Alice's public key.
```
keyPair = RSA.generate(1024) # assume this new key belongs to Alice.

pubKey = keyPair.publickey() 
pubKeyPEM = pubKey.exportKey()
print(pubKeyPEM.decode('ascii'))

privKeyPEM = keyPair.exportKey()
print(privKeyPEM.decode('ascii'))
```
2. Generates a fresh symmetric key for the data encapsulation scheme.
```
aesKey = os.urandom(16)
cipher = AES.new(aesKey, AES.MODE_EAX)
```
3. Encrypts the message using the symmetric key just generated.
```
message = b'A message for encryption'
ciphertext, tag = cipher.encrypt_and_digest(message)
```
4. Encrypts the symmetric key using Alice's public key.
```
encryptor = PKCS1_OAEP.new(pubKey)
encryptedKey = encryptor.encrypt(aesKey)
```
5. Sends both of these encryptions to Alice.

##### To decrypt this hybrid ciphertext, Alice does the following:
1. Uses her private key to decrypt the symmetric key.
```
decryptor = PKCS1_OAEP.new(keyPair)
decryptedAesKey = decryptor.decrypt(encryptedKey)
```
2. Uses this symmetric key to decrypt the message contained in the data encapsulation segment.
```
cipher = AES.new(decryptedAesKey, AES.MODE_EAX)
decryptedMessage = cipher.decrypt(ciphertext)
```