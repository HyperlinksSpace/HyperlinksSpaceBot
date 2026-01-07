# Vercel Analytics Setup Guide

## Why Analytics Might Not Be Working

If you see console logs but no data in Vercel, the most common reasons are:

### 1. Analytics Not Enabled in Vercel Settings ⚠️ (MOST COMMON)

**Solution:**
1. Go to your Vercel Dashboard
2. Select your project
3. Go to **Settings** → **Analytics**
4. Enable **"Web Analytics"**
5. **Redeploy** your application (important!)

### 2. Check Network Tab

Open browser DevTools (F12) → Network tab:
- Filter for `"insights"` or `"/_vercel/insights"`
- Look for requests to `/_vercel/insights/view` or `/_vercel/insights/script.js`
- Status should be **200** or **204**

If you see **404** or the request doesn't exist:
- Analytics is not enabled in Vercel
- Or the script path is wrong

### 3. Domain/Proxy Issues

If you're using a custom domain with a proxy (like Cloudflare):
- Make sure the proxy forwards requests to `/_vercel/insights/*`
- Some proxies block analytics scripts

### 4. Ad Blockers

Ad blockers can block analytics scripts:
- Disable ad blockers when testing
- Check if `window.va` exists in console: `console.log(window.va)`

## How to Verify It's Working

### Step 1: Check Console
Open browser console and look for:
```
✓ Vercel Analytics (va) detected
✓ Vercel Analytics initialized and ready
```

### Step 2: Check Network Requests
1. Open DevTools → Network tab
2. Filter: `insights`
3. You should see requests to `/_vercel/insights/view` with status 200/204

### Step 3: Check Vercel Dashboard
1. Go to Vercel Dashboard → Your Project
2. Click **Analytics** tab
3. You should see page views and events

### Step 4: Manual Test in Console
```javascript
// Check if va exists
console.log('va:', window.va);

// Check if vercelAnalytics wrapper exists
console.log('vercelAnalytics:', window.vercelAnalytics);

// Try to track an event manually
if (window.va && window.va.track) {
  window.va.track('test_event', { test: 'value' });
  console.log('Event tracked!');
}
```

## Current Implementation

The code now:
1. ✅ Waits for Vercel to auto-inject the script
2. ✅ Falls back to manual script loading if needed
3. ✅ Provides clear console messages
4. ✅ Handles errors gracefully

## Next Steps

1. **Enable Analytics in Vercel** (if not already done)
2. **Redeploy** your application
3. **Test on production URL** (not localhost)
4. **Check console** for initialization messages
5. **Wait 5-10 minutes** for data to appear in dashboard

## Troubleshooting

If still not working after enabling Analytics:

1. **Check Vercel Project Settings:**
   - Settings → Analytics → Web Analytics should be **ON**

2. **Verify Deployment:**
   - Make sure you're testing the **production** deployment
   - Analytics doesn't work on preview deployments

3. **Check Domain:**
   - If using custom domain, ensure it's properly configured
   - Try accessing via `*.vercel.app` URL to test

4. **Browser Console:**
   - Run: `console.log(window.va)`
   - Should show an object or function, not `undefined`

5. **Contact Vercel Support:**
   - If all else fails, Analytics might not be available for your plan
   - Check your Vercel plan includes Analytics

