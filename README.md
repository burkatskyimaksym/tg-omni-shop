# Telegram & WP E-Comers Project
## Project Pitch: The Vision  
**Project Title**: Omni-Channel AI Retail Engine (WordPress + Telegram Hybrid)  

**The Problem**: Modern e-commerce store owners lose customers because traditional website navigation can be overwhelming on mobile devices, yet running a separate standalone Telegram shop creates a data nightmare—requiring manual synchronization of stocks, prices, and orders across two independent systems.  
  
**The Solution**: A unified, intelligent retail ecosystem. Traditional shoppers use a highly responsive WordPress/WooCommerce web store. Mobile-first shoppers interact with an advanced AI-powered Telegram Bot that understands natural language and images. Both interfaces are dynamically bridged by a central FastAPI controller, ensuring zero lag, instant cross-platform inventory updates, and centralized business management.  
  
## Core Features (What It Actually Does)  
- **Omni-Channel Synchronization**: Real-time inventory and order matching via secure webhooks. An item sold on the website instantly drops stock levels within the Telegram bot's database cache, preventing accidental overselling.
- **AI Semantic Product Search**: Customers can chat with the bot casually (e.g., "Я шукаю щось тепле на зиму"), and the AI performs a vector similarity search via pgvector to find matching items, even if the exact keywords don't match the product titles.
- **Multimodal Visual Search**: Users can upload a screenshot or photo of an item they like directly into the Telegram chat. The AI vision embedding model processes the visual traits and surface matches from the local store catalog.
- **Context-Aware AI Customer Support**: The bot handles general store inquiries (returns, shipping rates, working hours) dynamically using an integrated Retrieval-Augmented Generation (RAG) knowledge base.  
- **Automated Checkout Pipeline**: A clean, secure state-machine checkout process inside Telegram that gathers customer data, handles shipping choices, updates the centralized MariaDB database, and initiates payment gateways without human intervention.  

## Technical Stack  
### Frontend & Management  
- **WordPress + WooCommerce**: The master storefront and business management dashboard.
- **MariaDB**: The optimized relational database handling the WordPress side.  
### Backend Middleware & Automation  
- **FastAPI**: The centralized microservice orchestrating API calls, handling webhooks, and routing data.
- **aiogram**: The asynchronous Python framework driving the high-speed Telegram bot interface.  
### Artificial Intelligence Layer (via OpenRouter)  
- **Llama Chat Brain (e.g., Llama 3.3 70B)**: The conversational engine managing tool calling and customer text responses.  
- **Llama Nemotron Embed VL**: The multimodal embedding model generating 2,048-dimensional concept vectors for text and images.  
### Vector Database  
- **PostgreSQL + pgvector**: The local vector storage and semantic search engine for the AI agent.  
### Payment Gateways & External Integrations  
- **Monobank API (Plata)**: Direct merchant integration for seamless mobile-first invoice generation inside Telegram.
- **LiqPay API**: Integrated secure payment pipeline utilizing cryptographic signature handshakes for verified webhooks.