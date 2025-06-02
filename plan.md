# EventSnap Implementation Plan

## Phase 1: Project Setup and Environment Configuration

### Step 1: Create Flutter Project Structure
- [x] **Tasks:**
  - [x] Initialize a new Flutter project with `flutter create --project-name event_snap_2`
  - [x] Set up proper folder structure (lib/screens, lib/models, lib/services, lib/widgets)
  - [x] Configure Git repository for version control
- [x] **Considerations:**
  - [x] Use latest stable Flutter version to ensure compatibility
  - [x] Establish naming conventions for files and classes early
- [x] **Definition of Done:**
  - [x] Project compiles without errors
  - [x] Folder structure established with placeholder files
  - [x] Initial commit to version control

### Step 2: Configure Dependencies
- [x] **Tasks:**
  - [x] Add and install all required dependencies to pubspec.yaml using `flutter pub add`, which gets the latest version.
    - [x] dart_openai (for OpenAI API integration)
    - [x] shared_preferences (for settings storage)
    - [x] flutter_secure_storage (for API key security)
    - [x] intl (for date formatting)
    - [x] path_provider (for file system access)
    - [x] url_launcher (for opening .ics files)
    - [x] ical (for iCalendar file generation)
    - [x] provider (for state management)
- [x] **Considerations:**
  - [x] Pin specific versions to ensure stability
  - [x] Review each package's license for compliance
- [x] **Definition of Done:**
  - [x] All dependencies successfully installed
  - [x] No package conflicts
  - [x] Example imports verify accessibility

### Step 3: Android Platform Configuration
- [x] **Tasks:**
  - [x] Configure AndroidManifest.xml to support text sharing
  - [x] Add required permissions (INTERNET, ACCESS_NETWORK_STATE)
  - [x] Set up MainActivity to handle shared text intents
  - [x] Create method channel for communication with Flutter
- [x] **Considerations:**
  - [x] Test on different Android API levels
  - [x] Ensure proper intent filter configuration for text sharing
- [x] **Definition of Done:**
  - [x] AndroidManifest.xml properly configured with:
    - [x] android:exported="true" for MainActivity
    - [x] Intent filters for MAIN/LAUNCHER and SEND/VIEW actions
    - [x] Text/plain MIME type configuration
  - [x] Method channel established between Android and Flutter
  - [x] Required permissions properly declared

## Phase 2: Data Models and Core Services

### Step 4: Implement Data Models
- [x] **Tasks:**
  - [x] Create EventModel class with all required fields
  - [x] Implement CalendarEventProperties class
  - [x] Develop Settings model for application configuration
  - [x] Add JSON serialization/deserialization for all models
- [x] **Considerations:**
  - [x] Ensure proper validation for each field
  - [x] Add documentation for class properties
- [x] **Definition of Done:**
  - [x]All data models implemented with proper typing
  - [x]JSON serialization/deserialization functions tested
  - [x]Models include validation logic where appropriate
  - [x]Unit tests verify model behavior

### Step 5: Implement AI Communication Service
- [ ] **Tasks:**
  - [x] Create CalendarEventInterpreter interface
  - [x] Implement OpenAiCalendarEventInterpreter using dart_openai SDK
  - [x] Develop prompt engineering with system messages and examples
  - [x] Implement error handling and retry logic
- [x] **Considerations:**
  - [x] Ensure dynamic date handling in prompts based on current date
  - [x] Handle API timeouts and rate limiting
  - [x] Properly secure API key usage
- [x] **Definition of Done:**
  - [x] Service successfully communicates with OpenAI API
  - [x] Structured JSON responses correctly parsed into EventModel
  - [x] Error handling covers network issues, invalid responses, etc.
  - [x] Prompt examples updated dynamically based on current date
  - [x] Unit tests with mock responses verify service behavior

### Step 6: Implement iCalendar Service
- [x] **Tasks:**
  - [x] Create CalendarCreator interface
  - [x] Implement ICalendarCreator using the ical package
  - [x] Develop file saving and sharing functionality
  - [x] Handle date/time formatting according to iCalendar standards
- [x] **Considerations:**
  - [x] Ensure proper timezone handling
  - [x] Generate unique UIDs for calendar events
- [x] **Definition of Done:**
  - [x] Service generates valid .ics files from event data
  - [x] Files saved properly to app's temporary directory
  - [x] Generated files validate against iCalendar standards
  - [x] Basic integration with platform file sharing is functional
  - [x] Unit tests verify .ics file generation

### Step 7: Implement Settings Management
- [x] **Tasks:**
  - [x] Create SettingsService for managing app configuration
  - [x] Implement secure storage of API keys
  - [x] Add functions for retrieving/updating settings
  - [x] Create default configuration values
- [x] **Considerations:**
  - [x] Never store API keys in plain text
  - [x] Handle migration of settings between app versions
- [x] **Definition of Done:**
  - [x] Settings securely stored using flutter_secure_storage
  - [x] API keys properly encrypted at rest
  - [x] Non-sensitive settings stored in shared_preferences
  - [x] Settings retrieval optimized with caching
  - [x] Unit tests verify settings persistence

## Phase 3: User Interface Implementation

### Step 8: Create Main Application Shell
- [x] **Tasks:**
  - [x] Implement Material app with theme configuration
  - [x] Set up navigation system (router or Navigator 2.0)
  - [x] Create app scaffold with consistent styling
  - [x] Implement state management foundation (Provider)
- [x] **Considerations:**
  - [x] Support for light/dark mode
  - [x] Responsive design principles
- [x] **Definition of Done:**
  - [x] App launches with consistent styling
  - [x] Navigation structure established
  - [x] State management framework implemented
  - [x] Theme support working

### Step 9: Implement Event Text Input Screen
- [x] **Tasks:**
  - [x] Create EventTextScreen with text input field
  - [x] Add submission button with loading state
  - [x] Implement connection to AI service
  - [x] Handle errors during text processing
- [x] **Considerations:**
  - [x] Provide clear input instructions to users
  - [x] Show appropriate loading indicators during API calls
- [x] **Definition of Done:**
  - [x] Screen allows text input with clear UI
  - [x] Submit button triggers AI processing
  - [x] Loading state properly displayed during processing
  - [x] Error states handled with user-friendly messages
  - [x] UI tested on different screen sizes

### Step 10: Implement Event Details Screen
- [x] **Tasks:**
  - [x] Create EventDetailsScreen with form fields for all event properties
  - [x] Implement validation for required fields
  - [x] Add "Add to Calendar" button functionality
  - [x] Connect to iCalendar service
- [x] **Considerations:**
  - [x] Intuitive date/time input for users
  - [x] Form validation with clear error messages
- [x] **Definition of Done:**
  - [x] Screen displays and allows editing of all event properties
  - [x] Form validation ensures valid event data
  - [x] "Add to Calendar" button generates and shares .ics file
  - [x] UI responds appropriately on different screen sizes
  - [x] Field focus and keyboard behavior optimized for mobile

### Step 11: Implement Settings Screen
- [x] **Tasks:**
  - [x] Create SettingsScreen for API key configuration
  - [x] Add fields for OpenAI model selection
  - [x] Implement secure API key input
  - [x] Connect to Settings service
- [x] **Considerations:**
  - [x] Mask API key display for security
  - [x] Provide clear instructions for obtaining API keys
- [x] **Definition of Done:**
  - [x] Screen allows secure input of OpenAI API key
  - [x] Model selection implemented with sensible defaults
  - [x] Settings changes properly persisted
  - [x] Input validation for API key format
  - [x] Help text guides users on obtaining API keys

## Phase 4: Android Share Integration

### Step 12: Implement Shared Text Handling
- [x] **Tasks:**
  - [x] Set up method channel in MainActivity.kt
  - [x] Implement Kotlin code to extract shared text from intents
  - [x] Create Flutter method channel handler
  - [x] Connect shared text to event processing flow
- [x] **Considerations:**
  - [x] Handle different intent types and sources: homescreen launch intent needs to open Home screen, but share intent needs to open EventTextInput screen
  - [x] Ensure app works when launched directly or via share
- [x] **Definition of Done:**
  - [x] App receives shared text from other applications
  - [x] Method channel successfully passes text to Flutter
  - [x] App processes shared text automatically
  - [x] Handles empty or invalid shared text gracefully

### Step 13: Calendar Integration
- [x] **Tasks:**
  - [x] Use intent launching for calendar apps
  - [x] Handle Android file provider configuration
  - [x] Add support for different calendar applications
- [x] **Considerations:**
  - [x] Handle devices without calendar apps installed
- [x] **Definition of Done:**
  - [x] Generated .ics files can be opened with calendar apps via the 'Add to Calendar' button
  - [x] Graceful handling when no compatible apps are found
  - [x] Tested with multiple calendar applications

## Phase 5: Prompt Engineering and AI Integration

### Step 14: Advanced Prompt Engineering
- [x] **Tasks:**
  - [x] Refine system prompt for optimal event extraction
  - [x] Create comprehensive example messages
  - [x] Implement dynamic date references in examples
  - [x] Optimize temperature and other model parameters
- [x] **Considerations:**
  - [x] Examples should cover various event types and formats
  - [x] Balance between specificity and generalization
- [x] **Definition of Done:**
  - [x] System prompt produces consistent, structured results
  - [x] Examples updated dynamically based on current date
  - [x] AI successfully extracts event details from various text formats
  - [x] Parameter tuning optimizes response quality
  - [x] Tested with diverse input formats and styles

### Step 15: Response Parsing and Validation
- [ ] **Tasks:**
  - [ ] Implement robust JSON parsing from API responses
  - [ ] Add validation for extracted event properties
  - [ ] Create fallback mechanisms for incomplete data
  - [ ] Implement reasonable defaults for missing information
- [ ] **Considerations:**
  - [ ] Handle malformed JSON gracefully
  - [ ] Validate dates for logical consistency (end after start)
- [ ] **Definition of Done:**
  - [ ] Parser extracts structured data from API responses
  - [ ] Validation catches and fixes common issues
  - [ ] Reasonable defaults applied for missing fields
  - [ ] Error handling for unexpected response formats
  - [ ] Unit tests verify parsing behavior with various responses

## Phase 6: Testing and Refinement

### Step 16: Unit and Widget Testing
- [ ] **Tasks:**
  - [ ] Implement unit tests for all services
  - [ ] Create widget tests for UI components
  - [ ] Set up mock services for testing
  - [ ] Add tests for critical user flows
- [ ] **Considerations:**
  - [ ] Focus on critical paths and error cases
  - [ ] Use mocks to avoid actual API calls in tests
- [ ] **Definition of Done:**
  - [ ] Unit tests cover all service classes
  - [ ] Widget tests verify UI behavior
  - [ ] All tests pass consistently
  - [ ] Test coverage meets predetermined targets
  - [ ] CI integration for automated testing

### Step 17: Integration Testing
- [ ] **Tasks:**
  - [ ] Create end-to-end tests for main user flows
  - [ ] Test Android share integration on real devices
  - [ ] Verify calendar integration with multiple apps
  - [ ] Test with various input formats and languages
- [ ] **Considerations:**
  - [ ] Test on multiple device types and Android versions
  - [ ] Include edge cases like poor network connectivity
- [ ] **Definition of Done:**
  - [ ] Integration tests verify complete user flows
  - [ ] Share functionality tested on multiple device types
  - [ ] Calendar integration verified with popular calendar apps
  - [ ] App behavior consistent across environments
  - [ ] Performance metrics within acceptable ranges

### Step 18: Performance Optimization
- [ ] **Tasks:**
  - [ ] Profile app for performance bottlenecks
  - [ ] Optimize state management to minimize rebuilds
  - [ ] Implement caching for API responses where appropriate
  - [ ] Reduce app size and memory footprint
- [ ] **Considerations:**
  - [ ] Balance between performance and code clarity
  - [ ] Focus on user-perceived performance
- [ ] **Definition of Done:**
  - [ ] App startup time within acceptable range
  - [ ] API calls optimized with appropriate caching
  - [ ] UI remains responsive during operations
  - [ ] Memory usage monitored and optimized
  - [ ] Frame rate consistently smooth during animations

### Step 19: Final Polishing and Documentation
- [ ] **Tasks:**
  - [ ] Add app icons and splash screen
  - [ ] Create README and developer documentation
  - [ ] Implement final UI tweaks based on testing feedback
  - [ ] Prepare for potential release
- [ ] **Considerations:**
  - [ ] Ensure all code is well-documented
  - [ ] Create user guide for initial users
- [ ] **Definition of Done:**
  - [ ] Complete app icons and branding elements
  - [ ] Comprehensive README with setup instructions
  - [ ] Code documented with comments and doc strings
  - [ ] UI consistent and polished across all screens
  - [ ] All known issues addressed or documented

This implementation plan provides a structured approach to building the EventSnap application based on the design document. Each step includes specific tasks, important considerations, and clear definitions of done to guide the development process.