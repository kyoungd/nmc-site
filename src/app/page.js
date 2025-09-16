export default function Home() {
  return (
    <main className="min-h-screen bg-light">
      <div className="container mx-auto px-4 py-8">
        <h1 className="text-4xl font-bold text-center mb-8">
          NeverMissCall Dashboard
        </h1>

        <div className="text-center space-y-6">
          <p className="text-lg text-accent">
            Professional call management dashboard for businesses
          </p>

          <div className="space-x-4">
            <button className="btn-primary">
              Get Started
            </button>
            <button className="btn-secondary">
              Learn More
            </button>
          </div>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6 mt-12">
          <div className="demo-card bg-white p-6 rounded-lg shadow-md">
            <h3 className="text-xl font-semibold mb-4">Call Management</h3>
            <p className="text-gray-600">Never miss important calls with our AI-powered system</p>
          </div>

          <div className="demo-card bg-white p-6 rounded-lg shadow-md">
            <h3 className="text-xl font-semibold mb-4">Real-time Dashboard</h3>
            <p className="text-gray-600">Monitor call activity and performance metrics in real-time</p>
          </div>

          <div className="demo-card bg-white p-6 rounded-lg shadow-md">
            <h3 className="text-xl font-semibold mb-4">Analytics</h3>
            <p className="text-gray-600">Get insights into your call patterns and customer interactions</p>
          </div>
        </div>
      </div>
    </main>
  )
}