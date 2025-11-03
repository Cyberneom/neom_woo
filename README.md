# neom_woo
neom_woo is a specialized module within the Open Neom ecosystem,
dedicated to integrating with the WooCommerce and WordPress APIs.
Its primary role is to serve as the gateway for all e-commerce
and content-related interactions with the commercial back-end. 

This module enables Open Neom to function as a platform for digital
and physical product sales, subscriptions, event bookings, and content delivery,
bridging the open-source front-end with the proprietary e-commerce infrastructure.
This module is a key component of the Open Core strategy, demonstrating how
a powerful open-source foundation can support a sophisticated commercial layer.
It encapsulates all WooCommerce-specific logic, data models, and API calls, exposing
its functionalities through a generic service interface (WooGatewayService in neom_core)
to maintain strict architectural decoupling. neom_woo embodies the Tecnozenism philosophy
by creating a sustainable economic model that supports the ongoing development and research of the Open Neom initiative.

🌟 Features & Responsibilities
neom_woo provides a comprehensive set of functionalities for WooCommerce integration:
•	Product & Content Retrieval:
    o	Fetches products (digital, physical, services) and their attributes from the WooCommerce API.
    o	Retrieves product variations, downloads, and related metadata.
    o	Integrates with WordPress APIs to handle media uploads and user authentication via JWT tokens.
•	Data Mapping & Orchestration:
    o	Maps complex WooCommerce API models (WooProduct, WooOrder, WooBilling, WooShipping, etc.)
        into Open Neom's universal data models (AppReleaseItem, Itemlist).
    o	Implements the WooGatewayService interface to provide a clean and consistent API for other modules
        (e.g., neom_timeline, neom_releases) to consume e-commerce data without being aware of WooCommerce's specifics.
•	Order Management:
    o	Contains logic for creating orders in WooCommerce, including handling line items, billing, and shipping details.
    o	Manages specific order types, such as nupale-session orders, which are crucial for the Cyberneom platform.
•	Media Uploads:
    o	Implements the WooMediaService interface for securely uploading media files to the WordPress backend,
        essential for releases and other content.
•	Web View Integration:
    o	Provides a WooWebViewPage to display the WooCommerce checkout and order pages, allowing users to complete
        transactions in a seamless web view.
    o	The WooWebViewController handles navigation, page state, and post-order processing (creating internal orders and transactions).
•	Payment Gateway Integration:
    o	Designed to handle and process various payment methods supported by WooCommerce.

🛠 Technical Highlights / Why it Matters (for developers)
For developers, neom_woo serves as an excellent case study for:
•	Enterprise-Level API Integration: Demonstrates how to build a robust and highly specialized gateway for a complex
    third-party e-commerce API (WooCommerce), including API calls, data serialization/deserialization, and authentication (JWT).
•	Clean Architecture Implementation: Provides a prime example of isolating a specific technology stack
    (WooCommerce) within a dedicated module, exposing its capabilities through a generic service interface
    (WooGatewayService) in the core domain.
•	Complex Data Mapping: Features detailed data mappers (WooProductMapper) for converting between complex API
    models and simple, universal project models, a crucial pattern for maintaining architectural cleanliness.
•	Secure Web View Handling: Shows how to securely integrate a web view for a checkout process, including filtering navigation,
    handling JavaScript injection, and creating internal records post-transaction.
•	GetX for State Management: Utilizes GetX for managing controller state (WooWebViewController)
    and orchestrating complex asynchronous operations (API calls, order processing).
•	Future-Proof Design: Its architecture is designed to handle a wide range of e-commerce functionalities,
    from products and subscriptions to bookings and variations, providing a scalable foundation for growth.

How it Supports the Open Neom Initiative
As a private module, neom_woo is the engine of Cyberneom's commercial operations. Its existence and its structured
integration with the public modules are vital for Open Neom by:
•	Ensuring a Sustainable Model: It provides the business and e-commerce infrastructure that funds the open-source
    development and research of the entire Open Neom ecosystem.
•	Validating the Open Core: neom_woo demonstrates that Open Neom's modular and decoupled architecture is not just
    a theoretical concept but a practical framework capable of supporting real-world, commercial applications.
•	Providing Clear Contribution Paths: It clarifies the distinction between the open core
    (where the community can contribute to the shared foundation) and
    the commercial applications (that are built on that foundation).

🚀 Usage
This module provides the WooGatewayService interface and its implementation, as well as the WooWebViewController
and related UI. It is consumed by other modules (e.g., neom_releases for creating new products, neom_timeline
for displaying release items, neom_bank for transaction processing) that require e-commerce functionalities.

📦 Dependencies
neom_woo relies on neom_core and neom_commons for shared services, models, and components. It also directly
depends on freezed_annotation for code generation and webview_flutter for its web view component.

🤝 Contributing
As a private module, contributions to neom_woo are not open. However, its architecture and its dependencies
on the Open Neom ecosystem provide a clear direction for where the community can contribute to the
public modules to support and enable this and other future functionalities.

To understand the broader architectural context of Open Neom and how neom_woo fits into the overall
vision of Tecnozenism, please refer to the main project's MANIFEST.md.

For guidance on how to contribute to Open Neom and to understand the various levels of learning and engagement
possible within the project, consult our comprehensive guide: Learning Flutter Through Open Neom: A Comprehensive Path.

📄 License
This project is licensed under the Apache License, Version 2.0, January 2004. See the LICENSE file for details.
