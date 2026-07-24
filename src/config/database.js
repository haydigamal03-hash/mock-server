export const initializeDatabase = async () => {
  try {
    console.log('[DATABASE] Initializing database connection...');
  } catch (error) {
    console.error('[DATABASE] Failed to initialize:', error.message);
    throw error;
  }
};