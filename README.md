# Private website hosting with CloudFront and Signed Cookies

## Table of Contents
- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

## Introduction
This project shows how to host a private website using CloudFront and Signed Cookies using terraform. Resources created
- `S3 Bucket`: A private S3 bucket to store the static files for the website. This bucket is only accessible by CloudFront with origin access identity (OAI).
- `CloudFront Distribution`: To serve the static content from edge serves right next to the users after upon successful authentication the user identity.
- `Lambda Function`: To validate user identity and return signed cookies on successful authentication.

## Prerequisites
- Terraform v1.4.x
- AWS Account

## Authentication flow
TODO: Add image and describe the flow

## Architectural considerations
TODO: Add decision points

## License
TODO: Provide information about the license.
