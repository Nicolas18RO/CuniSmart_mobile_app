# Product Requirements Document: CuniSmart MVP

## Product Overview

**App Name:** CuniSmart  
**Tagline:** Smart rabbit farming with IoT and accessible technology  
**Launch Goal:** Test the idea with real rabbit farmers  
**Target Launch:** 4–6 weeks  

---

## Who It's For

### Primary User: Rural Rabbit Farmer (Omar)

Small-scale agricultural entrepreneur who manages a rabbit farm using traditional methods. Some users may have visual impairments, including blindness.

**Their Current Pain:**
- No clear record of how many rabbits they have  
- Difficulty tracking animal data (age, breed, lineage)  
- No automated way to monitor conditions (temperature, water, weight)  
- Lack of accessible tools for visually impaired users  

**What They Need:**
- A simple way to register and track animals  
- Real-time monitoring of farm conditions  
- Voice-based interaction and audio feedback  
- Easy-to-use mobile interface  

### Example User Story

"Meet Omar, a small rabbit farmer who struggles to keep track of his animals and their information. He uses manual methods and cannot easily monitor important variables like weight or temperature. He needs a simple and accessible tool to manage his farm so he can make better decisions and improve productivity."

---

## The Problem We're Solving

Rabbit farmers, especially in rural areas, rely on manual and inefficient methods to manage their farms. This leads to poor tracking of animals, lack of control over environmental conditions, and missed opportunities to optimize production.

For visually impaired users, the problem is even bigger due to the lack of accessible digital tools.

**Why Existing Solutions Fall Short:**
- General agriculture apps: Not specialized for rabbit farming  
- IoT platforms: Too complex and not user-friendly  
- Manual methods: Inefficient and error-prone  

---

## User Journey

### Discovery → First Use → Success

1. **Discovery Phase**
   - Finds the app through recommendation or demonstration  
   - Interested in improving farm management  
   - Decides to try due to simplicity and voice features  

2. **Onboarding (First 5 Minutes)**
   - Opens the app  
   - Uses voice guidance to navigate  
   - Registers first rabbit  

3. **Core Usage Loop**
   - Trigger: Needs to check animals or conditions  
   - Action: Uses voice or simple UI  
   - Reward: Gets clear information  
   - Investment: Adds more animals and data  

4. **Success Moment**
   - Realizes all animals are organized  
   - Can monitor weight and conditions easily  
   - Gains confidence in managing the farm  

---

## MVP Features

### Must Have for Launch

#### 1. Animal Registration
- **What:** Store and manage data for each rabbit  
- **User Story:** As a farmer, I want to register my rabbits so I can track them easily  
- **Success Criteria:**
  - [ ] User can create, edit, and view animals  
  - [ ] Data is saved locally  
- **Priority:** P0 (Critical)

#### 2. Voice Navigation & Accessibility
- **What:** Navigate app using voice and audio feedback  
- **User Story:** As a visually impaired user, I want to use voice to interact with the app so I can use it independently  
- **Success Criteria:**
  - [ ] User can navigate main screens via voice  
  - [ ] App provides audio feedback  
- **Priority:** P0 (Critical)

#### 3. IoT Sensor Integration
- **What:** Receive data from sensors (weight, temperature, water)  
- **User Story:** As a farmer, I want to monitor conditions automatically so I can make better decisions  
- **Success Criteria:**
  - [ ] Sensor data is displayed in app  
  - [ ] Data updates periodically  
- **Priority:** P0 (Critical)

#### 4. Real-Time Alerts
- **What:** Notify user when conditions are abnormal  
- **User Story:** As a farmer, I want alerts so I can act quickly  
- **Success Criteria:**
  - [ ] Alerts triggered on thresholds  
  - [ ] Alerts include audio feedback  
- **Priority:** P0 (Critical)

#### 5. Simple Monitoring Dashboard
- **What:** Display key data in a simple interface  
- **User Story:** As a user, I want to quickly understand what's happening on my farm  
- **Success Criteria:**
  - [ ] Shows animals and sensor data  
  - [ ] Easy to understand layout  
- **Priority:** P0 (Critical)

---

### Nice to Have (If Time Allows)
- Basic statistics (average weight, trends)  
- Simple filtering of animals  

---

### NOT in MVP (Saving for Later)
- AI Predictions — after enough data is collected  
- Multi-user support — after initial validation  

*Why we're waiting: Keeps MVP simple and fast to launch*

---

## How We'll Know It's Working

### Launch Success Metrics (First 30 Days)

| Metric | Target | Measure |
|--------|--------|--------|
| Number of animals registered | 50+ | In-app data |
| Daily app usage | 5–10 users/day | App logs |

---

## Look & Feel

**Design Vibe:** Clean, simple, accessible, minimal, fast  

**Visual Principles:**
1. Clarity over complexity  
2. Accessibility first (voice + contrast)  
3. Minimal steps for each action  

**Key Screens:**
1. Dashboard  
2. Animal Registration  
3. Sensor Monitoring  
4. Alerts  

---

## Technical Considerations

**Platform:** Mobile (Android)  
**Responsive:** Mobile-first  
**Performance:** Lightweight, fast loading  

**Accessibility:**  
- Voice navigation  
- Audio feedback  
- Compatible with screen readers  

**Offline Support:**  
- Works without internet  
- Syncs when connection is available  

---

## Quality Standards

**What This App Will NOT Accept:**
- Broken features  
- Complex UI  
- Lack of accessibility  
- Features outside MVP scope  

---

## Budget & Constraints

**Development Budget:** Minimal — free tools only  
**Monthly Operating:** Near $0  
**Timeline:** 4–6 weeks  
**Team:** Solo developer  

---

## Open Questions & Assumptions

- What sensors will be used exactly?  
- How will IoT communication be handled?  
- Will users need training?  

---

## Launch Strategy (Brief)

**Soft Launch:**  
Test with 3–5 real farmers  

**Feedback Plan:**  
Direct interviews + observation  

**Iteration Cycle:**  
Weekly improvements  

---

## Definition of Done for MVP

The MVP is ready when:
- [ ] All core features work  
- [ ] App works offline  
- [ ] Voice features functional  
- [ ] One full user flow works  
- [ ] Tested with real users  

---

## Next Steps

1. Create Technical Design Document (Part 3)  
2. Set up development environment  
3. Build MVP  
4. Test with users  
5. Launch  

---

*Document created: May 2026*  
*Status: Ready for Technical Design*