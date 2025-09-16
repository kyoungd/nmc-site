const { PrismaClient } = require('@prisma/client')

const prisma = new PrismaClient()

async function main() {
  console.log('🌱 Starting seed...')

  // Create a test user
  const testUser = await prisma.user.upsert({
    where: { email: 'test@nevermisscall.com' },
    update: {},
    create: {
      clerkUserId: 'clerk_test_user_123',
      email: 'test@nevermisscall.com',
      name: 'Test User',
      phone: '+1234567890',
      globalRole: 'USER'
    }
  })

  console.log('👤 Created test user:', testUser.name)

  // Create a test business
  const testBusiness = await prisma.business.upsert({
    where: { id: 'test-business-id' },
    update: {},
    create: {
      id: 'test-business-id',
      displayName: 'Test Business',
      legalName: 'Test Business LLC',
      website: 'https://testbusiness.com',
      email: 'contact@testbusiness.com',
      phone: '+1987654321',
      industry: 'Technology',
      tz: 'America/New_York',
      brandColor: '#0A327F',
      langs: ['en'],
      hours: {
        monday: { open: '09:00', close: '17:00' },
        tuesday: { open: '09:00', close: '17:00' },
        wednesday: { open: '09:00', close: '17:00' },
        thursday: { open: '09:00', close: '17:00' },
        friday: { open: '09:00', close: '17:00' },
        saturday: { closed: true },
        sunday: { closed: true }
      },
      serviceAreas: {
        type: 'radius',
        center: { lat: 40.7128, lng: -74.0060 },
        radius: 25
      }
    }
  })

  console.log('🏢 Created test business:', testBusiness.displayName)

  // Create business user relationship
  await prisma.businessUser.upsert({
    where: {
      businessId_userId: {
        businessId: testBusiness.id,
        userId: testUser.id
      }
    },
    update: {},
    create: {
      businessId: testBusiness.id,
      userId: testUser.id,
      role: 'OWNER'
    }
  })

  // Create a test employee
  const testEmployee = await prisma.employee.upsert({
    where: {
      businessId_userId: {
        businessId: testBusiness.id,
        userId: testUser.id
      }
    },
    update: {},
    create: {
      businessId: testBusiness.id,
      userId: testUser.id,
      name: testUser.name,
      email: testUser.email,
      phone: testUser.phone,
      active: true
    }
  })

  console.log('👨‍💼 Created test employee:', testEmployee.name)

  // Create a test phone number
  const testPhoneNumber = await prisma.phoneNumber.upsert({
    where: { e164: '+15551234567' },
    update: {},
    create: {
      businessId: testBusiness.id,
      e164: '+15551234567',
      mmsCapable: true,
      status: 'ACTIVE',
      twilioSid: 'test_twilio_sid_123',
      activatedAt: new Date()
    }
  })

  console.log('📞 Created test phone number:', testPhoneNumber.e164)

  // Create a test contact
  const testContact = await prisma.contact.upsert({
    where: {
      businessId_e164: {
        businessId: testBusiness.id,
        e164: '+15559876543'
      }
    },
    update: {},
    create: {
      businessId: testBusiness.id,
      e164: '+15559876543',
      localePref: 'en'
    }
  })

  console.log('👥 Created test contact:', testContact.e164)

  // Create a test conversation
  const testConversation = await prisma.conversation.create({
    data: {
      businessId: testBusiness.id,
      contactId: testContact.id,
      phoneNumberId: testPhoneNumber.id,
      fromE164: testContact.e164,
      toE164: testPhoneNumber.e164,
      initialCallStatus: 'missed',
      responderMode: 'AI',
      outcome: 'SCHEDULED'
    }
  })

  console.log('💬 Created test conversation')

  // Create test messages
  await prisma.message.createMany({
    data: [
      {
        conversationId: testConversation.id,
        direction: 'OUT',
        medium: 'SMS',
        text: 'Hi! Thanks for calling Test Business. How can I help you today?',
        sender: 'AI',
        lang: 'en'
      },
      {
        conversationId: testConversation.id,
        direction: 'IN',
        medium: 'SMS',
        text: 'I need to schedule an appointment',
        sender: 'SYSTEM'
      },
      {
        conversationId: testConversation.id,
        direction: 'OUT',
        medium: 'SMS',
        text: 'I\'d be happy to help you schedule an appointment. What day works best for you?',
        sender: 'AI',
        lang: 'en'
      }
    ]
  })

  console.log('📝 Created test messages')

  // Create a test appointment
  const tomorrow = new Date()
  tomorrow.setDate(tomorrow.getDate() + 1)
  tomorrow.setHours(10, 0, 0, 0)

  const appointmentEnd = new Date(tomorrow)
  appointmentEnd.setHours(11, 0, 0, 0)

  await prisma.appointment.create({
    data: {
      businessId: testBusiness.id,
      contactId: testContact.id,
      employeeId: testEmployee.id,
      start: tomorrow,
      end: appointmentEnd,
      source: 'AI'
    }
  })

  console.log('📅 Created test appointment')

  // Create entitlement
  await prisma.entitlement.upsert({
    where: { businessId: testBusiness.id },
    update: {},
    create: {
      businessId: testBusiness.id,
      plan: 'FLAT',
      active: true,
      limitsJson: {
        maxPhoneNumbers: 1,
        maxEmployees: 1,
        maxConversationsPerMonth: 100
      }
    }
  })

  console.log('🎫 Created entitlement')

  console.log('✅ Seed completed successfully!')
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e)
    process.exit(1)
  })
  .finally(async () => {
    await prisma.$disconnect()
  })