# Phone Verification Modal - Frontend Test Checklist

## Test Environment
- **Browser**: Chrome/Firefox/Safari
- **Device**: Desktop & Mobile
- **Server**: Local development (`http://localhost:4000`)

---

## 1. Modal Open/Close Tests ✅

### Test 1.1: Modal Opens on Trigger
- [ ] Navigate to a page with phone verification trigger (member profile, post view)
- [ ] Click "Verify Phone" button or trigger element
- [ ] **Expected**: Modal appears with backdrop overlay
- [ ] **Expected**: Focus moves to phone number input field

### Test 1.2: Modal Closes on Backdrop Click
- [ ] Open modal
- [ ] Click on dark backdrop area (outside modal content)
- [ ] **Expected**: Modal closes and returns to previous page
- [ ] **Expected**: No error messages in console

### Test 1.3: Modal Closes on X Button
- [ ] Open modal
- [ ] Click X button in top-right corner
- [ ] **Expected**: Modal closes immediately
- [ ] **Expected**: Form state is reset

### Test 1.4: Modal Closes on Cancel Button
- [ ] Open modal
- [ ] Click "Cancel" button at bottom
- [ ] **Expected**: Modal closes
- [ ] **Expected**: No verification code is sent

### Test 1.5: Modal Does Not Close on Content Click
- [ ] Open modal
- [ ] Click inside modal content area (white box)
- [ ] **Expected**: Modal stays open
- [ ] **Expected**: No accidental close from inner clicks

---

## 2. Phone Number Formatting Tests ✅

### Test 2.1: US Format - Progressive Formatting
- [ ] Open modal
- [ ] Type digits one by one: `2345678900`
- [ ] **Expected After "2"**: `(2`
- [ ] **Expected After "234"**: `(234`
- [ ] **Expected After "2345"**: `(234) 5`
- [ ] **Expected After "2345678"**: `(234) 567-8`
- [ ] **Expected After "2345678900"**: `(234) 567-8900`

### Test 2.2: US Format - Leading "1" Stripped
- [ ] Open modal
- [ ] Type: `12345678900`
- [ ] **Expected**: `(234) 567-8900` (leading 1 removed)

### Test 2.3: International Format - Preserved
- [ ] Open modal
- [ ] Type: `+442079460958`
- [ ] **Expected**: `+442079460958` (no formatting, preserved as-is)

### Test 2.4: Format with Spaces/Dashes - Cleaned
- [ ] Open modal
- [ ] Type: `234-567-8900`
- [ ] **Expected**: `(234) 567-8900`

### Test 2.5: Paste Phone Number
- [ ] Copy `2345678900` to clipboard
- [ ] Paste into input field
- [ ] **Expected**: `(234) 567-8900`

### Test 2.6: Paste International Number
- [ ] Copy `+442079460958` to clipboard
- [ ] Paste into input field
- [ ] **Expected**: `+442079460958` (no formatting)

---

## 3. SMS Opt-in Checkbox Tests ✅

### Test 3.1: Checkbox Default Checked
- [ ] Open modal
- [ ] **Expected**: SMS opt-in checkbox is checked by default
- [ ] **Expected**: Helper text "Send me special offers..." is visible

### Test 3.2: Checkbox Can Be Unchecked
- [ ] Open modal
- [ ] Click checkbox to uncheck
- [ ] **Expected**: Checkbox unchecks
- [ ] Submit form (proceed to next test)
- [ ] **Expected**: `sms_opt_in=false` sent to server

### Test 3.3: Checkbox State Persists During Session
- [ ] Uncheck SMS opt-in
- [ ] Enter invalid phone number
- [ ] Submit form (error shown)
- [ ] **Expected**: Checkbox remains unchecked after error

### Test 3.4: Checkbox Cursor Pointer
- [ ] Hover over checkbox
- [ ] **Expected**: Cursor changes to pointer (clickable)
- [ ] Hover over label text
- [ ] **Expected**: Cursor changes to pointer (entire label clickable)

---

## 4. Error Message Tests ✅

### Test 4.1: Invalid Phone Format
- [ ] Enter: `123` (too short)
- [ ] Click "Send Code →"
- [ ] **Expected**: Red error banner with message like "Phone number is invalid"
- [ ] **Expected**: Error disappears when user starts typing again

### Test 4.2: Duplicate Phone Number
- [ ] Use phone number already verified by another user
- [ ] Click "Send Code →"
- [ ] **Expected**: Error "Phone number is already in use"

### Test 4.3: VoIP Number Detection (if Twilio lookup enabled)
- [ ] Enter known VoIP number (e.g., Google Voice)
- [ ] Click "Send Code →"
- [ ] **Expected**: Error "VoIP numbers not allowed for verification"

### Test 4.4: Rate Limiting Error
- [ ] Request code 3 times in quick succession
- [ ] Try 4th time
- [ ] **Expected**: Error "Too many attempts. Please try again in X minutes"

### Test 4.5: Wrong Verification Code
- [ ] Request code
- [ ] Enter incorrect 6-digit code
- [ ] Click "Verify Code"
- [ ] **Expected**: Red error "Invalid verification code"
- [ ] **Expected**: Input field remains, can retry

### Test 4.6: Expired Verification Code
- [ ] Request code
- [ ] Wait 11+ minutes
- [ ] Enter code
- [ ] **Expected**: Error "Verification code has expired"

### Test 4.7: Error Message Styling
- [ ] Trigger any error
- [ ] **Expected**: Red background (`bg-red-50`)
- [ ] **Expected**: Red border (`border-red-200`)
- [ ] **Expected**: Red text (`text-red-700`)
- [ ] **Expected**: Rounded corners, proper padding

---

## 5. Success State Tests ✅

### Test 5.1: Step 1 → Step 2 Transition
- [ ] Enter valid phone: `(234) 567-8900`
- [ ] Click "Send Code →"
- [ ] **Expected**: Step changes to "Enter Code"
- [ ] **Expected**: Green success banner "Code sent to +1 (234) 567-8900"
- [ ] **Expected**: Formatted phone number displayed
- [ ] **Expected**: Code input field auto-focused

### Test 5.2: Step 2 → Step 3 Transition
- [ ] Enter correct 6-digit code
- [ ] Click "Verify Code"
- [ ] **Expected**: Success screen appears
- [ ] **Expected**: Green checkmark icon
- [ ] **Expected**: "Phone Verified! 🎉" header
- [ ] **Expected**: Multiplier visualization (0.5x → 2.0x)

### Test 5.3: Success Screen - Multiplier Display
- [ ] Complete verification with US number
- [ ] **Expected**: Shows "2.0x" in green
- [ ] **Expected**: Shows country code "US"
- [ ] **Expected**: Shows tier "Premium"

### Test 5.4: Success Screen - Close Button
- [ ] Click "Start Reading →" button
- [ ] **Expected**: Modal closes
- [ ] **Expected**: User profile/page refreshes with new multiplier
- [ ] **Expected**: Phone verification badge/indicator appears

### Test 5.5: Success Message Formatting
- [ ] Complete verification
- [ ] **Expected**: Success banner has green styling
- [ ] **Expected**: Message is clear and encouraging
- [ ] **Expected**: No grammar/spelling errors

---

## 6. Resend Countdown Tests ✅

### Test 6.1: Countdown Starts After Code Sent
- [ ] Send verification code
- [ ] **Expected**: "Resend in 60s" button appears
- [ ] **Expected**: Button is disabled (gray, cursor not-allowed)

### Test 6.2: Countdown Decrements Every Second
- [ ] Watch resend button for 5 seconds
- [ ] **Expected**: "Resend in 60s" → "Resend in 59s" → ... → "Resend in 55s"
- [ ] **Expected**: Countdown updates smoothly

### Test 6.3: Countdown Reaches Zero
- [ ] Wait 60 seconds (or use browser dev tools to speed up)
- [ ] **Expected**: Button text changes to "Resend Code"
- [ ] **Expected**: Button becomes enabled (blue, cursor pointer)

### Test 6.4: Resend Button Works After Countdown
- [ ] Wait for countdown to finish
- [ ] Click "Resend Code"
- [ ] **Expected**: New code is sent
- [ ] **Expected**: Success message appears
- [ ] **Expected**: Countdown resets to 60s

### Test 6.5: Countdown Persists on Error
- [ ] Send code (countdown starts)
- [ ] Enter wrong code (error shown)
- [ ] **Expected**: Countdown continues ticking down
- [ ] **Expected**: Countdown not reset by error

### Test 6.6: Change Number Resets Flow
- [ ] Send code (countdown active)
- [ ] Click "Change Number"
- [ ] **Expected**: Returns to Step 1 (phone entry)
- [ ] **Expected**: Countdown is cleared
- [ ] **Expected**: Success/error messages cleared

---

## 7. Mobile Responsiveness Tests ✅

### Test 7.1: Modal Renders on Mobile
- [ ] Open modal on mobile device (or use Chrome DevTools mobile view)
- [ ] **Expected**: Modal fits screen width with padding
- [ ] **Expected**: All text is readable (not too small)
- [ ] **Expected**: Buttons are large enough to tap (44px minimum)

### Test 7.2: Phone Input on Mobile
- [ ] Tap phone input field
- [ ] **Expected**: Numeric keyboard appears (type="tel")
- [ ] **Expected**: No auto-zoom on iOS (font-size >= 16px)
- [ ] **Expected**: Input field stays visible when keyboard appears

### Test 7.3: Code Input on Mobile
- [ ] Tap code input field
- [ ] **Expected**: Numeric keyboard appears
- [ ] **Expected**: Large input (text-2xl) is readable
- [ ] **Expected**: Input field centered and clear

### Test 7.4: Buttons on Mobile
- [ ] Test all buttons (Send Code, Verify, Cancel, Resend)
- [ ] **Expected**: Easy to tap (no mis-taps)
- [ ] **Expected**: Proper spacing between buttons
- [ ] **Expected**: Hover states don't interfere on touch

---

## 8. Accessibility Tests ✅

### Test 8.1: Keyboard Navigation
- [ ] Open modal
- [ ] Press Tab key
- [ ] **Expected**: Focus moves through: phone input → checkbox → cancel → send
- [ ] Press Enter on "Send Code"
- [ ] **Expected**: Form submits

### Test 8.2: Focus Management
- [ ] Open modal
- [ ] **Expected**: Focus automatically moves to phone input
- [ ] Submit phone (move to Step 2)
- [ ] **Expected**: Focus automatically moves to code input

### Test 8.3: Screen Reader (if available)
- [ ] Enable VoiceOver (Mac) or NVDA (Windows)
- [ ] Navigate modal
- [ ] **Expected**: Labels are read correctly
- [ ] **Expected**: Error messages are announced
- [ ] **Expected**: Success messages are announced

### Test 8.4: Required Field Validation
- [ ] Leave phone input empty
- [ ] Try to submit
- [ ] **Expected**: Browser shows "Please fill out this field"
- [ ] **Expected**: Form does not submit

---

## 9. Integration with Parent LiveView Tests ✅

### Test 9.1: Modal Opens from Member Profile
- [ ] Navigate to member profile page
- [ ] Look for "Verify Phone" button/link
- [ ] Click button
- [ ] **Expected**: Modal opens

### Test 9.2: Modal Opens from Post View
- [ ] Navigate to post detail page
- [ ] Look for verification prompt
- [ ] Click trigger
- [ ] **Expected**: Modal opens

### Test 9.3: User Data Refreshes After Verification
- [ ] Complete verification flow
- [ ] Close modal
- [ ] **Expected**: User's multiplier updates in UI
- [ ] **Expected**: Verification badge/indicator appears
- [ ] **Expected**: "Verify Phone" prompt no longer shown

### Test 9.4: Modal Doesn't Break LiveView Updates
- [ ] Open modal
- [ ] Let other LiveView updates happen (new posts, comments, etc.)
- [ ] **Expected**: Modal stays open
- [ ] **Expected**: Background updates don't interfere

---

## 10. Edge Cases & Error Recovery ✅

### Test 10.1: Slow Network Simulation
- [ ] Enable "Slow 3G" in Chrome DevTools Network tab
- [ ] Submit phone number
- [ ] **Expected**: Loading state shown (button disabled/spinning)
- [ ] **Expected**: Success message appears when code sent
- [ ] **Expected**: No duplicate requests

### Test 10.2: Network Error
- [ ] Enable "Offline" in Chrome DevTools
- [ ] Try to submit phone
- [ ] **Expected**: Error message shown
- [ ] Re-enable network
- [ ] Try again
- [ ] **Expected**: Works correctly

### Test 10.3: Page Refresh During Verification
- [ ] Send verification code
- [ ] Refresh page (F5)
- [ ] **Expected**: Modal closes or reopens at correct step
- [ ] **Expected**: Verification state persists (if applicable)

### Test 10.4: Multiple Rapid Submissions
- [ ] Enter phone
- [ ] Click "Send Code" 5 times rapidly
- [ ] **Expected**: Only one code sent
- [ ] **Expected**: Button disabled after first click
- [ ] **Expected**: No duplicate SMS

---

## Test Results Summary

| Category | Tests | Passed | Failed | Notes |
|----------|-------|--------|--------|-------|
| Modal Open/Close | 5 | TBD | TBD | |
| Phone Formatting | 6 | TBD | TBD | |
| SMS Opt-in | 4 | TBD | TBD | |
| Error Messages | 7 | TBD | TBD | |
| Success State | 5 | TBD | TBD | |
| Resend Countdown | 6 | TBD | TBD | |
| Mobile Responsive | 4 | TBD | TBD | |
| Accessibility | 4 | TBD | TBD | |
| Integration | 4 | TBD | TBD | |
| Edge Cases | 4 | TBD | TBD | |
| **TOTAL** | **49** | **0** | **0** | **Not yet tested** |

---

## Manual Testing Instructions

To manually test the phone verification modal:

1. **Start the development server**:
   ```bash
   elixir --sname node1 -S mix phx.server
   ```

2. **Open the browser**:
   ```bash
   open http://localhost:4000
   ```

3. **Navigate to a page with phone verification**:
   - Member profile page: `/members/:id`
   - Post detail page: `/:slug`
   - Or any page where the modal can be triggered

4. **Run through the test checklist above**:
   - Check off each test as you complete it
   - Note any failures or unexpected behavior
   - Take screenshots of any bugs

5. **Update this file** with test results:
   - Mark tests as ✅ (pass) or ❌ (fail)
   - Add notes for any issues found
   - Calculate pass rate in summary table

---

## Known Issues / Notes

_(Add any bugs or issues discovered during testing here)_

- None yet

---

## Testing Completed By

- **Tester**: _(Your name)_
- **Date**: _(Date tested)_
- **Environment**: _(Browser, OS, device)_
- **Pass Rate**: _(X/49 tests passed)_
