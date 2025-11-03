### 1.0.0 - Initial Release & E-commerce Gateway Specialization
This release marks the initial official release (v1.0.0) of neom_woo as a new, independent module within the Open Neom ecosystem. This module is introduced to centralize all logic and functionalities related to the WooCommerce and WordPress APIs, serving as the official e-commerce gateway for the platform.

Key Architectural & Feature Improvements:

Major Architectural Changes:

neom_woo is now a dedicated, self-contained, and private module for all WooCommerce integration processes.

Service-Oriented Architecture:

The module's implementation (WooGatewayController, WooWebViewController) exclusively interacts with core functionalities through service interfaces (e.g., WooGatewayService, WooWebViewService), which are defined in neom_core. This promotes the Dependency Inversion Principle (DIP) and ensures that neom_core remains decoupled from proprietary e-commerce details.

Centralized E-commerce Logic:

neom_woo now fully encapsulates all logic for fetching products, mapping data models, and processing orders via the WooCommerce API.

It includes a secure web view (WooWebViewPage) for the checkout process, with a dedicated controller to handle web navigation and post-transaction processing.

Complex Data Mapping:

Implements WooProductMapper and other mappers to translate complex API models into Open Neom's simple, universal domain models (AppReleaseItem, Itemlist).

Module-Specific Constants & Models:

Introduced a complete set of WooProduct models and related classes, along with WooConstants, WooAttributeConstants, and enums to handle WooCommerce's data structures in a type-safe manner.

Enhanced Maintainability & Scalability:

As a dedicated and self-contained module, neom_woo is now easier to maintain and extend for future e-commerce features.

This aligns perfectly with the overall architectural vision of Open Neom, demonstrating how a robust open core can support a complex, private business layer.

Leverages Core Open Neom Modules:

Built upon neom_core and neom_commons for foundational services and shared UI components, ensuring seamless integration within the ecosystem.