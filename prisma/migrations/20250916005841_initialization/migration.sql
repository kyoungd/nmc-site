-- CreateEnum
CREATE TYPE "public"."GlobalRole" AS ENUM ('USER', 'BACKEND_ADMIN');

-- CreateEnum
CREATE TYPE "public"."BusinessRole" AS ENUM ('OWNER', 'ADMIN');

-- CreateEnum
CREATE TYPE "public"."ResponderMode" AS ENUM ('AI', 'HUMAN');

-- CreateEnum
CREATE TYPE "public"."MessageDirection" AS ENUM ('IN', 'OUT');

-- CreateEnum
CREATE TYPE "public"."MessageMedium" AS ENUM ('SMS');

-- CreateEnum
CREATE TYPE "public"."Sender" AS ENUM ('AI', 'EMPLOYEE', 'SYSTEM');

-- CreateEnum
CREATE TYPE "public"."ConversationOutcome" AS ENUM ('SCHEDULED', 'ABANDONED', 'ESCALATED', 'CLOSED');

-- CreateEnum
CREATE TYPE "public"."PhoneNumberStatus" AS ENUM ('PENDING_ACTIVATION', 'ACTIVE', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "public"."A2PStatus" AS ENUM ('DRAFT', 'SUBMITTED', 'PENDING_CARRIERS', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "public"."AppointmentSource" AS ENUM ('AI', 'HUMAN');

-- CreateEnum
CREATE TYPE "public"."CalendarProvider" AS ENUM ('GOOGLE', 'JOBBER');

-- CreateEnum
CREATE TYPE "public"."Plan" AS ENUM ('FLAT');

-- CreateEnum
CREATE TYPE "public"."AfterHoursBehavior" AS ENUM ('AIONLY', 'QUEUE_FOR_HUMAN', 'CLOSE_WITH_MSG');

-- CreateEnum
CREATE TYPE "public"."PriceUnit" AS ENUM ('PER_JOB', 'PER_HOUR', 'PER_VISIT');

-- CreateEnum
CREATE TYPE "public"."DoubleBookPolicy" AS ENUM ('NODOUBLE', 'ALLOW_WITH_WARN');

-- CreateTable
CREATE TABLE "public"."User" (
    "id" TEXT NOT NULL,
    "clerkUserId" TEXT NOT NULL,
    "email" TEXT,
    "phone" TEXT,
    "name" TEXT,
    "globalRole" "public"."GlobalRole" NOT NULL DEFAULT 'USER',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."BusinessUser" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" "public"."BusinessRole" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BusinessUser_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Business" (
    "id" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "legalName" TEXT,
    "website" TEXT,
    "email" TEXT,
    "phone" TEXT,
    "industry" TEXT,
    "tz" TEXT NOT NULL,
    "brandColor" TEXT,
    "langs" TEXT[],
    "hours" JSONB NOT NULL,
    "serviceAreas" JSONB NOT NULL,
    "ringWindowSec" INTEGER NOT NULL DEFAULT 20,
    "ownerWindowSec" INTEGER NOT NULL DEFAULT 60,
    "afterHoursBehavior" "public"."AfterHoursBehavior" NOT NULL DEFAULT 'AIONLY',
    "doubleBookPolicy" "public"."DoubleBookPolicy" NOT NULL DEFAULT 'NODOUBLE',
    "stripeCustomerId" TEXT,
    "stripeSubscriptionId" TEXT,
    "a2pStatus" "public"."A2PStatus" NOT NULL DEFAULT 'DRAFT',
    "a2pBrandId" TEXT,
    "a2pCampaignId" TEXT,
    "a2pLastCarrierReason" TEXT,
    "teamSizeLimit" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Business_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Employee" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "userId" TEXT,
    "name" TEXT,
    "email" TEXT,
    "phone" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Employee_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."PhoneNumber" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "e164" TEXT NOT NULL,
    "mmsCapable" BOOLEAN NOT NULL DEFAULT true,
    "status" "public"."PhoneNumberStatus" NOT NULL DEFAULT 'PENDING_ACTIVATION',
    "twilioSid" TEXT,
    "reservedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
    "activatedAt" TIMESTAMP(3),
    "a2pCampaignId" TEXT,

    CONSTRAINT "PhoneNumber_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Contact" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "e164" TEXT NOT NULL,
    "localePref" TEXT,
    "optOutAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Contact_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Conversation" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "contactId" TEXT,
    "phoneNumberId" TEXT,
    "fromE164" TEXT NOT NULL,
    "toE164" TEXT NOT NULL,
    "initialCallSid" TEXT,
    "initialCallAt" TIMESTAMP(3),
    "initialCallStatus" TEXT,
    "openedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "closedAt" TIMESTAMP(3),
    "responderMode" "public"."ResponderMode" NOT NULL DEFAULT 'AI',
    "outcome" "public"."ConversationOutcome",
    "metadata" JSONB,

    CONSTRAINT "Conversation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Message" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "direction" "public"."MessageDirection" NOT NULL,
    "medium" "public"."MessageMedium" NOT NULL DEFAULT 'SMS',
    "text" TEXT NOT NULL,
    "lang" TEXT,
    "sender" "public"."Sender" NOT NULL DEFAULT 'SYSTEM',
    "employeeId" TEXT,
    "userId" TEXT,
    "providerSid" TEXT,
    "carrierStatus" TEXT,
    "carrierErrorCode" TEXT,
    "deliveredAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Message_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."CalendarAccount" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "provider" "public"."CalendarProvider" NOT NULL,
    "externalAccountId" TEXT NOT NULL,
    "scopes" TEXT[],
    "refreshTokenRef" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CalendarAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Appointment" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "contactId" TEXT,
    "employeeId" TEXT,
    "start" TIMESTAMP(3) NOT NULL,
    "end" TIMESTAMP(3) NOT NULL,
    "source" "public"."AppointmentSource" NOT NULL DEFAULT 'AI',
    "externalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Appointment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Entitlement" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "plan" "public"."Plan" NOT NULL DEFAULT 'FLAT',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "limitsJson" JSONB NOT NULL DEFAULT '{}',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Entitlement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."A2PArtifact" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "brandLegalName" TEXT NOT NULL,
    "ein" TEXT NOT NULL,
    "website" TEXT NOT NULL,
    "contactName" TEXT NOT NULL,
    "contactEmail" TEXT NOT NULL,
    "contactPhone" TEXT NOT NULL,
    "useCase" TEXT NOT NULL DEFAULT 'CUSTOMER_CARE',
    "sampleMessages" JSONB NOT NULL,
    "status" "public"."A2PStatus" NOT NULL DEFAULT 'SUBMITTED',
    "brandId" TEXT,
    "campaignId" TEXT,
    "carrierReason" TEXT,
    "submittedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
    "approvedAt" TIMESTAMP(3),
    "rejectedAt" TIMESTAMP(3),

    CONSTRAINT "A2PArtifact_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."TemplateSet" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "instantTextBack" TEXT NOT NULL,
    "schedulingPrompt" TEXT NOT NULL,
    "confirmation" TEXT NOT NULL,
    "cancellation" TEXT NOT NULL,
    "humanTakeover" TEXT NOT NULL,
    "stopHelp" TEXT NOT NULL,
    "linkPageBrandUrl" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TemplateSet_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ServicePricing" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "minPrice" DECIMAL(10,2) NOT NULL,
    "maxPrice" DECIMAL(10,2) NOT NULL,
    "unit" "public"."PriceUnit" NOT NULL DEFAULT 'PER_JOB',
    "notes" TEXT,

    CONSTRAINT "ServicePricing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."OnboardingProgress" (
    "id" TEXT NOT NULL,
    "businessId" TEXT NOT NULL,
    "wizardVersion" INTEGER NOT NULL DEFAULT 2,
    "page1Critical" BOOLEAN NOT NULL DEFAULT false,
    "page2Critical" BOOLEAN NOT NULL DEFAULT false,
    "page3Critical" BOOLEAN NOT NULL DEFAULT false,
    "page4Critical" BOOLEAN NOT NULL DEFAULT false,
    "lastStep" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OnboardingProgress_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_clerkUserId_key" ON "public"."User"("clerkUserId");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "public"."User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "BusinessUser_businessId_userId_key" ON "public"."BusinessUser"("businessId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "Business_stripeCustomerId_key" ON "public"."Business"("stripeCustomerId");

-- CreateIndex
CREATE UNIQUE INDEX "Employee_businessId_userId_key" ON "public"."Employee"("businessId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "PhoneNumber_e164_key" ON "public"."PhoneNumber"("e164");

-- CreateIndex
CREATE UNIQUE INDEX "PhoneNumber_twilioSid_key" ON "public"."PhoneNumber"("twilioSid");

-- CreateIndex
CREATE INDEX "PhoneNumber_businessId_idx" ON "public"."PhoneNumber"("businessId");

-- CreateIndex
CREATE INDEX "Contact_businessId_idx" ON "public"."Contact"("businessId");

-- CreateIndex
CREATE UNIQUE INDEX "Contact_businessId_e164_key" ON "public"."Contact"("businessId", "e164");

-- CreateIndex
CREATE INDEX "Conversation_businessId_openedAt_idx" ON "public"."Conversation"("businessId", "openedAt");

-- CreateIndex
CREATE INDEX "Conversation_businessId_fromE164_idx" ON "public"."Conversation"("businessId", "fromE164");

-- CreateIndex
CREATE INDEX "Message_conversationId_createdAt_idx" ON "public"."Message"("conversationId", "createdAt");

-- CreateIndex
CREATE INDEX "Message_providerSid_idx" ON "public"."Message"("providerSid");

-- CreateIndex
CREATE INDEX "CalendarAccount_businessId_employeeId_idx" ON "public"."CalendarAccount"("businessId", "employeeId");

-- CreateIndex
CREATE INDEX "Appointment_businessId_start_idx" ON "public"."Appointment"("businessId", "start");

-- CreateIndex
CREATE UNIQUE INDEX "Entitlement_businessId_key" ON "public"."Entitlement"("businessId");

-- CreateIndex
CREATE UNIQUE INDEX "A2PArtifact_businessId_key" ON "public"."A2PArtifact"("businessId");

-- CreateIndex
CREATE UNIQUE INDEX "TemplateSet_businessId_key" ON "public"."TemplateSet"("businessId");

-- CreateIndex
CREATE INDEX "ServicePricing_businessId_name_idx" ON "public"."ServicePricing"("businessId", "name");

-- CreateIndex
CREATE UNIQUE INDEX "OnboardingProgress_businessId_key" ON "public"."OnboardingProgress"("businessId");

-- AddForeignKey
ALTER TABLE "public"."BusinessUser" ADD CONSTRAINT "BusinessUser_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."BusinessUser" ADD CONSTRAINT "BusinessUser_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Employee" ADD CONSTRAINT "Employee_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Employee" ADD CONSTRAINT "Employee_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."PhoneNumber" ADD CONSTRAINT "PhoneNumber_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Contact" ADD CONSTRAINT "Contact_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Conversation" ADD CONSTRAINT "Conversation_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Conversation" ADD CONSTRAINT "Conversation_contactId_fkey" FOREIGN KEY ("contactId") REFERENCES "public"."Contact"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Conversation" ADD CONSTRAINT "Conversation_phoneNumberId_fkey" FOREIGN KEY ("phoneNumberId") REFERENCES "public"."PhoneNumber"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Message" ADD CONSTRAINT "Message_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "public"."Conversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Message" ADD CONSTRAINT "Message_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "public"."Employee"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Message" ADD CONSTRAINT "Message_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."CalendarAccount" ADD CONSTRAINT "CalendarAccount_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."CalendarAccount" ADD CONSTRAINT "CalendarAccount_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "public"."Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Appointment" ADD CONSTRAINT "Appointment_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Appointment" ADD CONSTRAINT "Appointment_contactId_fkey" FOREIGN KEY ("contactId") REFERENCES "public"."Contact"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Appointment" ADD CONSTRAINT "Appointment_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "public"."Employee"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Entitlement" ADD CONSTRAINT "Entitlement_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."A2PArtifact" ADD CONSTRAINT "A2PArtifact_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."TemplateSet" ADD CONSTRAINT "TemplateSet_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ServicePricing" ADD CONSTRAINT "ServicePricing_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."OnboardingProgress" ADD CONSTRAINT "OnboardingProgress_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "public"."Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;
